//
//  utils.hpp
//  drive_native_hydrator
//
//  Created by admin on 6/10/20.
//  Copyright © 2020 admin. All rights reserved.
//

#include <iostream>
#include <string>
#include <EndpointSecurity/EndpointSecurity.h>

#ifndef utils_hpp
#define utils_hpp

using std::string ;


namespace utils {
    
        const void print(string output);
        const char* FilenameFromPath(const char* path);
        const bool FileIsBeingHydrated(string filePath);
        const bool FileIsReparsePoint(string filePath);
        const char* GetProcessFileName(es_message_t* message);
        const bool PathLiesWithinTarget(const char* path, const char* target);

}

namespace xattr {

    const bool FileHasXattr(string filePath, string attribute);

    struct XattrKeys
    {
        const string imanage_prefix = "com.iManage.drive" ;
        const string is_reparse = this->imanage_prefix + ".is_reparse";
        const string jid = this->imanage_prefix + ".jid";
        const string hydrating = this->imanage_prefix + ".hydrating";
    };
}

#endif /* utils_h */
