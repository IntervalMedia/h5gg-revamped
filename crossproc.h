#ifndef crossproc_h
#define crossproc_h

#import <Foundation/Foundation.h>
#import <sys/sysctl.h>
#import <mach-o/dyld_images.h>
#import <mach-o/loader.h>

extern "C" {
#include "dyld64.h"
#include "libproc.h"
#include "proc_info.h"
}

NSArray<NSDictionary<NSString*, id>*>* _Nullable getRunningProcess(void);
pid_t pid_for_name(const char* _Nonnull name);
size_t getMachoVMSize(pid_t pid, task_port_t task, mach_vm_address_t addr);
NSArray<NSDictionary<NSString*, NSString*>*>* _Nullable getRangesList2(pid_t pid, task_port_t task, NSString* _Nullable filter);

#endif /* crossproc_h */
