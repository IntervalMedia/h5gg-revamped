#include "crossproc.h"
#include <libgen.h>
#include <errno.h>
#include <stdlib.h>

NSArray<NSDictionary<NSString*, id>*>* _Nullable getRunningProcess(void) {
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    u_int miblen = 4;
    size_t size;

    int st = sysctl(mib, miblen, NULL, &size, NULL, 0);
    NSLog(@"allproc=%d, %s", st, strerror(errno));

    struct kinfo_proc* process = nullptr;
    struct kinfo_proc* newprocess = nullptr;

    do {
        size += size / 10;
        newprocess = (struct kinfo_proc*)realloc(process, size);
        if(!newprocess) {
            free(process);
            return nil;
        }
        process = newprocess;
        st = sysctl(mib, miblen, process, &size, NULL, 0);
        NSLog(@"allproc=%d, %s", st, strerror(errno));
    } while(st == -1 && errno == ENOMEM);

    if(st == 0 && size % sizeof(struct kinfo_proc) == 0) {
        int nprocess = (int)(size / sizeof(struct kinfo_proc));
        if(nprocess) {
            NSMutableArray* array = [[NSMutableArray alloc] init];
            for(int i = nprocess - 1; i >= 0; i--) {
                [array addObject:@{
                    @"pid": @(process[i].kp_proc.p_pid),
                    @"name": @(process[i].kp_proc.p_comm)
                }];
            }
            free(process);
            NSLog(@"allproc=%d, %@", (int)array.count, array);
            return array;
        }
    }

    free(process);
    return nil;
}

pid_t pid_for_name(const char* name) {
    NSArray* allproc = getRunningProcess();
    for(NSDictionary* proc in allproc) {
        if([proc[@"name"] isEqualToString:@(name)])
            return [proc[@"pid"] intValue];
    }
    return 0;
}

size_t getMachoVMSize(pid_t pid, task_port_t task, mach_vm_address_t addr) {
    struct proc_regionwithpathinfo rwpi = {};
    proc_pidinfo(pid, PROC_PIDREGIONPATHINFO, addr, &rwpi, PROC_PIDREGIONPATHINFO_SIZE);

    if(!rwpi.prp_vip.vip_vi.vi_stat.vst_dev && !rwpi.prp_vip.vip_vi.vi_stat.vst_ino)
        return 0;

    struct mach_header_64 header;
    mach_vm_size_t hdrsize = sizeof(header);
    kern_return_t kr = mach_vm_read_overwrite(task, addr, hdrsize, (mach_vm_address_t)&header, &hdrsize);
    if(kr != KERN_SUCCESS || hdrsize != sizeof(header))
        return 0;

    mach_vm_size_t lcsize = header.sizeofcmds;
    if(lcsize < sizeof(struct load_command))
        return 0;

    void* buf = malloc(lcsize);
    if(!buf)
        return 0;

    kr = mach_vm_read_overwrite(task, addr + hdrsize, lcsize, (mach_vm_address_t)buf, &lcsize);
    if(kr == KERN_SUCCESS) {
        uint64_t vm_end = 0;
        uint64_t header_vaddr = -1;

        auto* lc = (struct load_command*)buf;
        char* commandEnd = (char*)buf + lcsize;
        for(uint32_t i = 0; i < header.ncmds; i++) {
            if((char*)lc + sizeof(*lc) > commandEnd ||
               lc->cmdsize < sizeof(*lc) ||
               (char*)lc + lc->cmdsize > commandEnd) {
                vm_end = 0;
                break;
            }

            if(lc->cmd == LC_SEGMENT_64) {
                if(lc->cmdsize < sizeof(struct segment_command_64)) {
                    vm_end = 0;
                    break;
                }
                auto* seg = (struct segment_command_64*)lc;

                if(seg->fileoff == 0 && seg->filesize > 0) {
                    if(header_vaddr != (uint64_t)-1) {
                        NSLog(@"multi header mapping! %s", seg->segname);
                        vm_end = 0;
                        break;
                    }
                    header_vaddr = seg->vmaddr;
                }

                if(seg->vmsize && vm_end < (seg->vmaddr + seg->vmsize))
                    vm_end = seg->vmaddr + seg->vmsize;
            }
            lc = (struct load_command*)((char*)lc + lc->cmdsize);
        }

        if(vm_end && header_vaddr != (uint64_t)-1)
            vm_end -= header_vaddr;

        free(buf);
        return (size_t)vm_end;
    }

    free(buf);
    return 0;
}

NSArray<NSDictionary<NSString*, NSString*>*>* _Nullable getRangesList2(pid_t pid, task_port_t task, NSString* _Nullable filter) {
    NSMutableArray* results = [[NSMutableArray alloc] init];

    task_dyld_info_data_t task_dyld_info = {};
    mach_msg_type_number_t count = TASK_DYLD_INFO_COUNT;
    kern_return_t kr = task_info(task, TASK_DYLD_INFO, (task_info_t)&task_dyld_info, &count);
    NSLog(@"getmodules TASK_DYLD_INFO=%p %llx %d",
          (void*)task_dyld_info.all_image_info_addr, (unsigned long long)task_dyld_info.all_image_info_size,
          task_dyld_info.all_image_info_format);

    if(kr != KERN_SUCCESS)
        return results;

    struct dyld_all_image_infos64 aii;
    mach_vm_size_t aiiSize = sizeof(aii);
    kr = mach_vm_read_overwrite(task, task_dyld_info.all_image_info_addr, aiiSize,
                                (mach_vm_address_t)&aii, &aiiSize);

    NSLog(@"getmodules all_image_info %d %p %d", aii.version, (void*)aii.infoArray, aii.infoArrayCount);
    if(kr != KERN_SUCCESS)
        return results;

    mach_vm_address_t ii = aii.infoArray;
    uint32_t iiCount = aii.infoArrayCount;
    if(iiCount > UINT32_MAX / sizeof(struct dyld_image_info64))
        return results;

    mach_msg_type_number_t iiSize = iiCount * sizeof(struct dyld_image_info64);

    kr = mach_vm_read(task, ii, iiSize, (vm_offset_t*)&ii, &iiSize);
    if(kr != KERN_SUCCESS) {
        NSLog(@"getmodules cannot read aii");
        return results;
    }

    auto* ii64 = (struct dyld_image_info64*)ii;
    for(int i = 0; i < iiCount; i++) {
        mach_vm_address_t addr = ii64[i].imageLoadAddress;
        mach_vm_address_t path = ii64[i].imageFilePath;

        NSLog(@"getmodules image[%d] %p %p", i, (void*)addr, (void*)path);

        char pathbuffer[PATH_MAX] = {};
        mach_vm_size_t size3 = sizeof(pathbuffer) - 1;
        if(mach_vm_read_overwrite(task, path, sizeof(pathbuffer) - 1,
                                  (mach_vm_address_t)pathbuffer, &size3) != KERN_SUCCESS)
            strcpy(pathbuffer, "<Unknown>");
        else
            pathbuffer[MIN(size3, sizeof(pathbuffer) - 1)] = '\0';

        NSLog(@"getmodules path=%s", pathbuffer);

        NSString *name = [NSString stringWithUTF8String:pathbuffer];
        NSString *baseName = [NSString stringWithUTF8String:basename(pathbuffer)];
        BOOL matches = (filter == nil)
            || (i == 0 && [filter isEqual:@"0"])
            || [filter isEqual:baseName];

        if(matches) {
            uint64_t size = getMachoVMSize(pid, task, (uint64_t)addr);
            uint64_t end = size ? ((uint64_t)addr + size) : 0;

            [results addObject:@{
                @"name": name,
                @"start": [NSString stringWithFormat:@"0x%llX", addr],
                @"end": [NSString stringWithFormat:@"0x%llX", end],
            }];

            if(i == 0 && [filter isEqual:@"0"]) break;
        }
    }

    vm_deallocate(mach_task_self(), ii, iiSize);
    return results;
}
