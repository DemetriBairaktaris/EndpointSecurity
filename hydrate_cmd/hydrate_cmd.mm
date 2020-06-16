
#include <stdio.h>
#include <copyfile.h>
#include <EndpointSecurity/EndpointSecurity.h>
#include <cstdio>
#include <dispatch/dispatch.h>
#include <cstring>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/errno.h>
#include <string>
#include <cstdlib>
#include <mutex>
#include <unordered_map>
#include <vector>
#include <bsm/libbsm.h>
#include <atomic>
#include <mach/mach_time.h>
#include <iostream>
#include <sstream>
#include "stdlib.h"
#include <filesystem>


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

const void HandleSecurityEvent(es_client_t* _Nonnull client, const es_message_t* _Nonnull message);
const static bool PathLiesWithinTarget(const char* path, const char* target);

static es_client_t* client = nullptr;
static dispatch_queue_t s_hydrationQueue = nullptr;
static mutex s_hydrationMutex;
static pid_t selfpid;
static char* targetDir;
static atomic_uint s_pendingAuthCount(0);
static unordered_map<string, vector<es_message_t*>> s_waitingFileHydrationMessages;


const static bool PathLiesWithinTarget(const char* path, const char* target){
    string target_str = string(target);
    return 0 == strncmp(target, path, target_str.length());
    
}

const void dispatch_sleep(es_client_t* _Nonnull client, es_message_t* _Nonnull message){
    
    
    int seconds = 62;
    const char *eventPath = message->event.open.file->path.data ;
    
    printf("Sleeping for %d seconds until accepting file open event.\n", seconds);
    sleep(seconds);
    
    printf("Denying Event, %s should not open.\n", eventPath);
    es_respond_flags_result(client, message, 0x0, false);
    std::atomic_fetch_sub(&s_pendingAuthCount, 1u);
    es_free_message(message);
    
    
    
    vector<es_message_t*> waitingMessages ;
    
    {
        Guard lock (s_hydrationMutex);
        s_waitingFileHydrationMessages[eventPath].swap(waitingMessages);
        s_waitingFileHydrationMessages.erase(eventPath);
    }
    
    while (!waitingMessages.empty()){
        es_message_t * current = waitingMessages.back();
        waitingMessages.pop_back();
        es_respond_flags_result(client, current, 0x0, false);
        std::atomic_fetch_sub(&s_pendingAuthCount, 1u);
        es_free_message(current);
    }
    
}


const void HandleSecurityEvent(es_client_t* _Nonnull client, const es_message_t* _Nonnull message){
    
    if (message->action_type == ES_ACTION_TYPE_AUTH) {
        if (message->event_type == ES_EVENT_TYPE_AUTH_OPEN) {
            pid_t pid = audit_token_to_pid(message->process->audit_token);
            if (selfpid == pid)
            {
                es_mute_process(client, &message->process->audit_token);
                es_respond_flags_result(client, message, 0x7fffffff, false);
                std::atomic_fetch_sub(&s_pendingAuthCount, 1u);
                return ;
            }
                
            const char *eventPath = message->event.open.file->path.data ;
            if(PathLiesWithinTarget(eventPath, targetDir)){
                Guard lock(s_hydrationMutex);
                if (!s_waitingFileHydrationMessages.insert(make_pair(eventPath, vector<es_message_t*>())).second){
                    s_waitingFileHydrationMessages[eventPath].push_back(es_copy_message(message));
                    return;
                }
                dispatch_async(s_hydrationQueue, ^{
                    dispatch_sleep(client, es_copy_message(message));
                });
                return;
            }
            
            std::atomic_fetch_sub(&s_pendingAuthCount, 1u);
            es_respond_flags_result(client, message, 0x7fffffff, false);
        }
        else{
            std::atomic_fetch_sub(&s_pendingAuthCount, 1u);
            es_respond_auth_result(client, message, ES_AUTH_RESULT_ALLOW, false);
        }
    }
}






int main(int argc, const char * argv[]) {
    
    printf("Starting Endpoint Security Program.\n");
    targetDir= "/Users/admin/Documents/" ; //TODO Set this to a test directory with files inside of it. Make sure it has a '/' on the end.

    
    printf("Your target directory is %s\n", targetDir);
    selfpid = getpid();
    
    
    struct stat sourceDirStat = {};
    
    if (0 != stat(targetDir, &sourceDirStat))
    {
        perror("stat() on target directory failed\n");
        return 1;
    }

    if (!S_ISDIR(sourceDirStat.st_mode))
    {
        fprintf(stderr, "Target Directory (%s) is not a directory.\n", targetDir);
        return 1;
    }

    // The dispatch queue used for processing hydration requests.
    // Note: concurrent, i.e. multithreaded.
    s_hydrationQueue = dispatch_queue_create("com.imanage.drive.cmd.hydrationqueue", DISPATCH_QUEUE_CONCURRENT);
    
    
    
    es_new_client_result_t result = es_new_client(
        &client,
        ^(es_client_t* _Nonnull client, const es_message_t* _Nonnull message)
        {
            std::atomic_fetch_add(&s_pendingAuthCount, 1u);
            HandleSecurityEvent(client, message);
        });
    
    if (result != ES_NEW_CLIENT_RESULT_SUCCESS)
    {
        fprintf(stderr, "es_new_client failed, error = %u\n", result);
        perror("Error ");
        return 1;
    }

    es_clear_cache(client);
    es_event_type_t subscribe_events[] = {ES_EVENT_TYPE_AUTH_OPEN};
    if (ES_RETURN_SUCCESS != es_subscribe(client, subscribe_events, extent<decltype(subscribe_events)>::value))
    {
        fprintf(stderr, "es_subscribe failed\n");
        return 1;
    }
    
    dispatch_main();
    return 0;
}


