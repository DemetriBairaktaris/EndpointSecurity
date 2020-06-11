#include "utils.h"


using xattr::XattrKeys;

const XattrKeys xattrKeys ;

const void utils::print(string output){
    std::cout << output << std::endl;
}


const char* utils::GetProcessFileName(es_message_t* _Nonnull message){
    return utils::FilenameFromPath(message->process->executable->path.data);
}


const bool utils::PathLiesWithinTarget(const char* path, const char* target){
    return 0 == strncmp(target, path, strlen(target));
}


const bool utils::FileIsReparsePoint(string filePath){
    return xattr::FileHasXattr(filePath, xattrKeys.is_reparse);
    
}


const char* utils::FilenameFromPath(const char* path){
    const char* lastSlash = std::strrchr(path, '/');
    if (lastSlash == nullptr)
    {
        return path;
    }
    else
    {
        return lastSlash + 1;
    }
}




const bool utils::FileIsBeingHydrated(string filePath){
    bool isBeingHydrated = xattr::FileHasXattr(filePath, xattrKeys.hydrating);
    if (isBeingHydrated) { utils::print("File is currently being hydrated"); }
    else { utils::print("File is not being currently hydrated"); }
    return isBeingHydrated ;
}



const bool xattr::FileHasXattr(string filePath, string attribute){
    char xattrBuffer[16];
    ssize_t xattrBytes = getxattr(filePath.c_str(), attribute.c_str(), xattrBuffer, sizeof(xattrBuffer), 0 /* offset */, 0 /* options */);
      return xattrBytes >= 0;
}


