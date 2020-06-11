#include "main.h"

using std::string;
using std::mutex;
using std::unordered_map;
using std::vector;
using std::atomic_uint;
using std::extent;
using std::to_string;
using std::cout;
using std::ostringstream;

typedef std::lock_guard<mutex> Guard;

struct Information
{
    string hostname = "";
    string targetDirectory = "";
    const ssize_t allowOpen = 0x7fffffff ;
    const ssize_t denyOpen = 0x0 ;
    //const xattr::XattrKeys xattrkeys ;
};

static Information information ;
static xattr::XattrKeys xattrKeys ;

static es_client_t* client = nullptr;
static dispatch_queue_t s_hydrationQueue = nullptr;
static mutex s_hydrationMutex;
static pid_t selfpid;
static string s_targetPrefix;
static atomic_uint s_pendingAuthCount(0);
static unordered_map<string, vector<es_message_t*>> s_waitingFileHydrationMessages;
static mach_timebase_info_data_t s_machTimebase;



const int hydrator::init(string hostname, string targetDir){
    
    utils::print("Starting hydrator");
    information.targetDirectory = string(targetDir);
    information.hostname = string(hostname);
    

    //Step 1.
    //information.mirrorDirectory = string(argv[1]);


    // Sanity check on the target dir, must be a dir.
    const char* const dir = information.targetDirectory.c_str();
    struct stat sourceDirStat = {};
    
    if (0 != stat(dir, &sourceDirStat))
    {
        perror("stat() on source directory failed");
        return 1;
    }

    if (!S_ISDIR(sourceDirStat.st_mode))
    {
        fprintf(stderr, "Mirror Directory (%s) is not a directory.\n", dir);
        return 1;
    }

    selfpid = getpid();
    mach_timebase_info(&s_machTimebase); // required for subsequent mach time <-> nsec/usec conversions
    
    // The dispatch queue used for processing hydration requests.
    // Note: concurrent, i.e. multithreaded.
    s_hydrationQueue = dispatch_queue_create("org.vfsforgit.endpointsecuritymirror.hydrationqueue", DISPATCH_QUEUE_CONCURRENT);
    
    
    // Ensure we have paths with trailing slashes for both source and target, so
    // that simple string prefix tests will suffice from here on out.
    char* absoluteTargetDir = realpath(information.targetDirectory.c_str(), NULL);
    s_targetPrefix = absoluteTargetDir;
    free(absoluteTargetDir);
    if (s_targetPrefix[s_targetPrefix.length() - 1] != '/')
        s_targetPrefix.append("/");
    information.targetDirectory = s_targetPrefix;

    printf("iManage Drive Hydrator is monitoring target dir='%s'\n", information.targetDirectory.c_str());

    // Perform the EndpointSecurity start-up:
    // Create client object, clear cache, and subscribe to events we're interested in.
    es_new_client_result_t result = es_new_client(
        &client,
        ^(es_client_t* _Nonnull client, const es_message_t* _Nonnull message)
        {
            std::atomic_fetch_add(&s_pendingAuthCount, 1u);
            hydrator::HandleSecurityEvent(client, message);
        });
    if (result != ES_NEW_CLIENT_RESULT_SUCCESS)
    {
        fprintf(stderr, "es_new_client failed, error = %u\n", result);
        return 1;
    }

    es_clear_cache(client); // This may no longer be necessary; without it, early macOS 10.15 betas would drop events.
    
    es_event_type_t subscribe_events[] = { ES_EVENT_TYPE_AUTH_OPEN, ES_EVENT_TYPE_NOTIFY_LOOKUP };
    if (ES_RETURN_SUCCESS != es_subscribe(client, subscribe_events, extent<decltype(subscribe_events)>::value))
    {
        fprintf(stderr, "es_subscribe failed\n");
        return 1;
    }
    
    // Handle events until process is killed
    dispatch_main();
}


const void hydrator::HandleSecurityEvent(es_client_t* _Nonnull client, const es_message_t* _Nonnull message){
    if (message->action_type == ES_ACTION_TYPE_AUTH) {
        if (message->event_type == ES_EVENT_TYPE_AUTH_OPEN) {
            pid_t pid = audit_token_to_pid(message->process->audit_token);
            if (pid == selfpid){
                
                printf("Handle Event Called.");
                printf("Muting events from self (pid %d)\n", pid);
                es_mute_process(client, &message->process->audit_token);
                
                es_respond_result_t result = es_respond_flags_result(client, message, 0x7fffffff, false /* don't cache */);
                assert(result == ES_RESPOND_RESULT_SUCCESS);
                std::atomic_fetch_sub(&s_pendingAuthCount, 1u);
                return;
            }
            
            const char* eventPath = message->event.open.file->path.data;
            
            ssize_t allowOpen = 0x7fffffff;
            bool cache = false;
            
            if (utils::PathLiesWithinTarget(eventPath, information.targetDirectory.c_str())){
    allowOpen = hydrator::HydrateFileOrAwaitHydration(eventPath, message);
                if (allowOpen == 0x0){
                    printf("Disallowing open from process %s", utils::GetProcessFileName(es_copy_message(message)));
                    return;
                }

            }
        
           
            unsigned count = std::atomic_fetch_sub(&s_pendingAuthCount, 1u);

            if (count != 1){
                //printf("224: In-flight authorisation requests pending: %u\n", count - 1);
            }
            es_respond_result_t result = es_respond_flags_result(client, message, allowOpen, cache /* don't cache */);
            //assert(result == ES_RESPOND_RESULT_SUCCESS);
        }
        else{
            fprintf(stderr, "Unexpected event type: %u\n", message->event_type);
        }
    }
    else{
        //printf("Unexpected action type: %u, event type: %u\n", message->action_type, message->event_type);
        unsigned count = std::atomic_fetch_sub(&s_pendingAuthCount, 1u);
        if (count != 1)
        {
            int allowOpen = 0x7fffffff;
            bool cache = true;
            
            
            es_respond_result_t result = es_respond_flags_result(client, message, allowOpen, cache);
            
            //printf("In-flight authorisation requests pending: %u\n", count - 1);
        }
    }
}



const int hydrator::HydrateFileOrAwaitHydration(string eventPath, const es_message_t* _Nonnull message){
    es_message_t* messageCopy = es_copy_message(message);
    Guard lock(s_hydrationMutex);
    
    int allowOpen = 0x7fffffff;
    int denyOpen = 0x0;
    bool cache = false;
    string processName = utils::GetProcessFileName(es_copy_message(message));
    std::cout << "Process name is Hydrating or awaiting: " << processName << std::endl ;
    
    if (processName.find("Python") != string::npos){
        std::cout << "Python allowed to open file" << std::endl;
        return allowOpen;
    }
    
    if (!s_waitingFileHydrationMessages.insert(make_pair(eventPath, vector<es_message_t*>())).second)
    {
        // already being hydrated, add to messages needing approval
        printf("File '%s' already being hydrated by another thread\n", eventPath.c_str());
        s_waitingFileHydrationMessages[eventPath].push_back(messageCopy);
        if (utils::FileIsBeingHydrated(eventPath)){
            return denyOpen ;
        }
        
        return allowOpen;
    }
    else
    {
        if (!std::__fs::filesystem::is_directory(string(eventPath))){
            if (utils::FileIsReparsePoint(eventPath)){
                dispatch_async(s_hydrationQueue, ^{
                    hydrator::RequestHydrate(eventPath, message);
                });
            }
        }
        
        return allowOpen ;
    }
    return allowOpen;
}

const void hydrator::RequestHydrate(string filePath, const es_message_t* _Nonnull message){
    //TODO figure out a way to do https requests. This http 'library' was taken from a github as quick solution.
    
    std::cout << "Requesting hydration" << std::endl;
    string url = "http://" + information.hostname + "/hydrate";
    
    char jid[64]  ;
    ssize_t jid_result = getxattr(filePath.c_str(), xattrKeys.jid.c_str(), &jid, 64, 0, 0);
    
    if (jid_result < 0){
        perror(("Failed to get JID from xattr, could not hydrate document=" + filePath).c_str());
        return ;
    }
    
    string jid_str(jid);
    jid_str.resize(jid_result);
    
    ostringstream body_out;
    body_out << "{" << "\"jid\":" << "\"" << jid_str << "\"," << "\"path\":" << "\"" <<filePath << "\""<<"}" ;
    string body = body_out.str();
    printf("JSON body = %s \n", body.c_str());
    utils::print("-------------------------------------------");
    
   try
    {
        http::Request request(url);
        // send a post request
        
        setxattr(filePath.c_str(), xattrKeys.hydrating.c_str(), "", 0, 0, 0);
        const http::Response response = request.send("POST", body, {
            "Content-Type: application/json"
        });
        
        std::cout << std::string(response.body.begin(), response.body.end()) << '\n'; // print the result
        utils::print("-------------------------------------------");
        
        removexattr(filePath.c_str(), xattrKeys.hydrating.c_str(), 0 /* options */);
        if (response.status > 299){
            return;
        }
        //it seems better to remove the xattr in this than in python. Too slow in python, at least in pycharm.
        //if we get to this point in the try statement we succeeded hydration.
        //remove xattr
        int result = removexattr(filePath.c_str(), xattrKeys.is_reparse.c_str(), 0 /* options */);
        if (result != 0)
        {
            perror("removexattr failed");
        }
        
        
        //Try iterating through all???
        
        es_respond_flags_result(client, message, 0x7fffffff, false);
        
        
        vector<es_message_t*> waitingMessages;
        
        {
            // Atomically remove the list of waiting messages from the global map indexed by filename
            Guard lock(s_hydrationMutex);
             s_waitingFileHydrationMessages[filePath].swap(waitingMessages);
             s_waitingFileHydrationMessages.erase(filePath);
        }

        if (!waitingMessages.empty())
            printf("Responding to %zu other auth events for file '%s'\n", waitingMessages.size(), filePath.c_str());

        while (!waitingMessages.empty())
        {
            es_message_t* waitingMessage = waitingMessages.back();
            waitingMessages.pop_back();

            es_respond_result_t response_result = es_respond_flags_result(client, waitingMessage, information.allowOpen, false /* don't cache */);
            
            es_free_message(waitingMessage);
        }
    }
    catch (const std::exception& e)
    {
        std::cerr << "Request failed, error: " << e.what() << '\n';
    }
}




