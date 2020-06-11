//
//  main.hpp
//  drive_native_hydrator
//
//  Created by admin on 6/10/20.
//  Copyright © 2020 admin. All rights reserved.
//

#ifndef main_hpp
#define main_hpp

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
#include "HTTPRequest.h"
#include <filesystem>
#include "main.h"
#include "utils.h"


using std::string;
using std::mutex;
using std::unordered_map;
using std::vector;
using std::atomic_uint;
using std::extent;
using std::to_string;
using std::cout;
using std::ostringstream;


namespace hydrator {

    const int init(string hostname, string targetDir);
    const void RequestHydrate(string filePath, const es_message_t* _Nonnull message);
    const void HandleSecurityEvent(es_client_t* _Nonnull client,
                                   const es_message_t* _Nonnull message);
    const int HydrateFileOrAwaitHydration(string eventPath,
                                          const es_message_t* _Nonnull message);

}

#endif /* main_hpp */
