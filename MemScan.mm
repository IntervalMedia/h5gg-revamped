#include "MemScan.h"
#include <pthread.h>
#include <Foundation/Foundation.h>
#include <cctype>
#include <cstdlib>

const int JJ_Search_Type_Len[] = {0, 8, 8, 8, 4, 4, 4, 2, 2, 1, 1};

result_region::result_region(uint64_t base, size_t size)
    : region_base(base), region_size(size) {}

#pragma mark - JJMemoryEngine

JJMemoryEngine::JJMemoryEngine(mach_port_t task) {
    this->task = task;
    this->result = new Result;
    this->result->count = 0;
    this->firstScanDone = false;
    this->float_tolerance = 0.0;
    this->lastNumberType = 0;
}

JJMemoryEngine::~JJMemoryEngine() {
    freeResults();
}

void JJMemoryEngine::freeResults() {
    if(result->count != 0) {
        for(auto* region : result->regions) {
            region->slides.clear();
            region->slides.shrink_to_fit();
            delete region;
        }
    }
    result->regions.clear();
    result->regions.shrink_to_fit();
    delete result;
}

bool JJMemoryEngine::readMemory(void* buf, uint64_t addr, size_t len) {
    vm_size_t size = 0;
    kern_return_t kr = vm_read_overwrite(this->task, (vm_address_t)addr, len, (vm_address_t)buf, &size);
    if(kr != KERN_SUCCESS || size != len) {
        NSLog(@"readMemory failed! %p %zu, (%d)%s", (void*)addr, len, kr, mach_error_string(kr));
        return false;
    }
    return true;
}

bool JJMemoryEngine::writeMemory(void* address, void *target, size_t len) {
    kern_return_t kr = vm_write(this->task, (vm_address_t)address, (vm_offset_t)target, (mach_msg_type_number_t)len);
    if(kr != KERN_SUCCESS) {
        NSLog(@"writeMemory failed! %p %zu", address, len);
        return false;
    }
    return true;
}

template<typename T>
static uint64_t ScanForValue(uint64_t p, uint64_t end, int len, void* target, float tolerance) {
    T v0 = static_cast<T*>(target)[0];
    T v1 = static_cast<T*>(target)[1];
    if constexpr (is_floating_point_v<T>) {
        v0 -= tolerance;
        v1 += tolerance;
    }
    while(p <= end) {
        T v = *reinterpret_cast<T*>(p);
        if(v >= v0 && v <= v1) break;
        p += len;
    }
    return p;
}

uint64_t JJMemoryEngine::ScanData(uint64_t buffer, uint64_t size, void* target, int type) {
    int len = JJ_Search_Type_Len[type];
    uint64_t end = buffer + size - len;
    uint64_t p = buffer;

    switch(type) {
        case JJ_Search_Type_Float:  p = ScanForValue<float>(p, end, len, target, float_tolerance); break;
        case JJ_Search_Type_Double: p = ScanForValue<double>(p, end, len, target, float_tolerance); break;
        case JJ_Search_Type_SByte:  p = ScanForValue<int8_t>(p, end, len, target, 0); break;
        case JJ_Search_Type_UByte:  p = ScanForValue<uint8_t>(p, end, len, target, 0); break;
        case JJ_Search_Type_SShort: p = ScanForValue<int16_t>(p, end, len, target, 0); break;
        case JJ_Search_Type_UShort: p = ScanForValue<uint16_t>(p, end, len, target, 0); break;
        case JJ_Search_Type_SInt:   p = ScanForValue<int32_t>(p, end, len, target, 0); break;
        case JJ_Search_Type_UInt:   p = ScanForValue<uint32_t>(p, end, len, target, 0); break;
        case JJ_Search_Type_SLong:  p = ScanForValue<int64_t>(p, end, len, target, 0); break;
        case JJ_Search_Type_ULong:  p = ScanForValue<uint64_t>(p, end, len, target, 0); break;
    }
    return p <= end ? p : 0;
}

void* JJMemoryEngine::loadRegion(uint64_t base, uint64_t* psize, bool* remapped) {
    size_t size = *psize;
    for(size_t s = 0; s < size; s += PAGE_SIZE) {
        uint64_t a = 0;
        if(vm_read_overwrite(this->task, (vm_address_t)(base + s), sizeof(a), (vm_address_t)&a, (vm_size_t*)&a) != KERN_SUCCESS) {
            size = s;
            break;
        }
    }

    if(!size) return nullptr;

    *psize = size;

    vm_address_t buffer = 0;
    vm_prot_t cur_prot = 0;
    vm_prot_t max_prot = 0;

    do {
        if(this->task == mach_task_self()) {
            mach_port_t object_name;
            mach_vm_size_t region_size = size;
            mach_vm_address_t region_base = base;

            vm_region_extended_info info = {};
            mach_msg_type_number_t info_cnt = VM_REGION_EXTENDED_INFO_COUNT;
            vm_region_flavor_t flavor = VM_REGION_EXTENDED_INFO;

            kern_return_t kr = mach_vm_region(this->task, &region_base, &region_size,
                                              flavor, (vm_region_info_t)&info, &info_cnt, &object_name);
            if(kr == KERN_SUCCESS && info.user_tag == VM_MEMORY_MALLOC_NANO) {
                *remapped = false;
                buffer = base;
                break;
            }
        }

        kern_return_t kr = vm_remap(mach_task_self(), &buffer, size, 0, VM_FLAGS_ANYWHERE,
                                    this->task, base, false, &cur_prot, &max_prot, VM_INHERIT_NONE);
        if(kr != KERN_SUCCESS) {
            NSLog(@"read mem failed! %p %zu, %d %s", (void*)base, size, kr, mach_error_string(kr));
            if(kr == KERN_NO_SPACE)
                throw bad_alloc();
        } else {
            *remapped = true;
        }
    } while(0);

    NSLog(@"loadRegion[%d] %p=>%p %zu,%x,%x", *remapped, (void*)base, (void*)buffer, size, cur_prot, max_prot);
    return (void*)buffer;
}

void JJMemoryEngine::unloadRegion(void* buffer, uint64_t size, bool remapped) {
    if(buffer && remapped) {
        NSLog(@"unloadRegion %p %llu", buffer, (unsigned long long)size);
        vm_deallocate(mach_task_self(), (vm_address_t)buffer, size);
    }
}

void JJMemoryEngine::ScanRegion(AddrRange range, uint64_t base, uint64_t size, void* target, int type) {
    int len = JJ_Search_Type_Len[type];

    result_region* newRegion = nullptr;

    bool remapped = false;
    void* buffer = loadRegion(base, &size, &remapped);

    if(buffer) {
        uint64_t pcurdata = (uint64_t)buffer;
        uint64_t left_size = size;
        while(left_size >= (uint64_t)len) {
            uint64_t pfound = ScanData(pcurdata, left_size, target, type);
            if(!pfound) break;

            uint32_t slide = (uint32_t)(pfound - (uint64_t)buffer);

            if((base + slide) < range.start || (base + slide) >= range.end) break;

            if(!newRegion)
                newRegion = new result_region(base, size);

            newRegion->slides.push_back(slide);
            this->result->count++;

            pcurdata = pfound + len;
            left_size = (uint64_t)buffer + size - pcurdata;
        }
    }

    if(newRegion) {
        newRegion->slides.shrink_to_fit();
        this->result->regions.push_back(newRegion);
    }

    unloadRegion(buffer, size, remapped);
}

void JJMemoryEngine::FirstScan(AddrRange range, void* target, int type) {

    size_t stack_size = pthread_get_stacksize_np(pthread_self());
    size_t stack_addr = (size_t)pthread_get_stackaddr_np(pthread_self());
    size_t stack_end = stack_addr + stack_size;
    NSLog(@"stack=%p %zu => %p", (void*)stack_addr, stack_size, (void*)stack_end);

    vm_size_t region_size = 0;
    vm_address_t region_base = range.start;

    natural_t depth = 1;

    while(region_base < range.end) {
        region_base += region_size;

        vm_region_submap_info_64 info = {};
        mach_msg_type_number_t info_cnt = VM_REGION_SUBMAP_INFO_COUNT_64;

        kern_return_t kr = vm_region_recurse_64(this->task, &region_base, &region_size,
                                                &depth, (vm_region_info_t)&info, &info_cnt);

        if(kr != KERN_SUCCESS) {
            NSLog(@"mach_vm_region failed on %p for %d,%s", (void*)region_base, kr, mach_error_string(kr));
            break;
        }

        const char* tag = name_for_tag(info.user_tag);
        NSLog(@"found region %p %lx [%d/%d], %x, %s", (void*)region_base, (unsigned long)region_size, info.is_submap, depth, info.protection, tag);

        if(info.is_submap) {
            region_size = 0;
            depth++;
            continue;
        }

        uint64_t region_end = (uint64_t)region_base + region_size;

        if(this->task == mach_task_self()) {
            if((stack_addr >= (uint64_t)region_base && stack_addr < region_end)
               || (stack_end > (uint64_t)region_base && stack_addr <= region_end)) {
                NSLog(@"skip stack region!");
                continue;
            }
        }

        if(!(info.protection & VM_PROT_WRITE)) {
            NSLog(@"skip readonly region!");
            continue;
        }

        this->regions[region_base] = region_size;
    }

    vector<pair<uint64_t, uint64_t>> regionsToScan;
    for(auto& [base, size] : this->regions) {
        if(base < range.start) continue;
        if(base > range.end) break;
        uint64_t region_end = min(base + size, range.end);
        regionsToScan.push_back({max(base, range.start), region_end - max(base, range.start)});
    }

    int i = 0;
    for(auto& [base, size] : regionsToScan) {
        NSLog(@"handle region[%d/%zu] %p %llx [%zu]", i++, regionsToScan.size(),
              (void*)base, (unsigned long long)size, this->result->count);
        ScanRegion(range, base, size, target, type);
    }

    this->result->regions.shrink_to_fit();
}

void JJMemoryEngine::ScanAgain(AddrRange range, void* target, int type) {
    int len = JJ_Search_Type_Len[type];

    size_t newCount = 0;

    for(int i = 0; i < this->result->regions.size(); i++) {
        result_region* region = this->result->regions[i];

        NSLog(@"handle region [%d/%zu]%zu %p %zx", i, this->result->regions.size(), region->slides.size(),
              (void*)region->region_base, region->region_size);

        if((region->region_base + region->region_size) < range.start || region->region_base > range.end)
            continue;

        result_region* newRegion = nullptr;

        bool remapped = false;
        uint64_t mapsize = region->region_size;
        void* buffer = loadRegion(region->region_base, &mapsize, &remapped);

        if(buffer) {
            for(int j = 0; j < region->slides.size(); j++) {
                uint64_t address = region->region_base + region->slides[j];
                void* pvalue = (void*)((uint64_t)buffer + region->slides[j]);

                if(address >= range.start && address < range.end &&
                   ScanData((uint64_t)pvalue, len, target, type)) {
                    if(!newRegion)
                        newRegion = new result_region(region->region_base, region->region_size);

                    newRegion->slides.push_back(region->slides[j]);
                    newCount++;
                }
            }
        } else {
            NSLog(@"read mem failed! [%d] %p %zx", i, (void*)region->region_base, region->region_size);
        }

        unloadRegion(buffer, mapsize, remapped);

        delete this->result->regions[i];
        this->result->regions[i] = newRegion;
        if(newRegion) newRegion->slides.shrink_to_fit();
    }

    this->result->regions.erase(
        remove(this->result->regions.begin(), this->result->regions.end(), (result_region*)nullptr),
        this->result->regions.end());

    this->result->regions.shrink_to_fit();
    this->result->count = newCount;
}

void JJMemoryEngine::SetFloatTolerance(float d) {
    this->float_tolerance = d;
}

void JJMemoryEngine::JJScanMemory(AddrRange range, void* target, int type) {
    if(type <= 0 || type >= JJ_Search_Type_Max) return;

    this->lastNumberType = type;

    if(this->firstScanDone) {
        ScanAgain(range, target, type);
    } else {
        FirstScan(range, target, type);
        this->firstScanDone = true;
    }

    saveSnapshot();
}

void JJMemoryEngine::JJScanHexMemory(AddrRange range, const char* hexStr) {
    vector<uint8_t> pattern;
    while(*hexStr) {
        while(*hexStr && isspace(*hexStr)) hexStr++;
        if(!*hexStr) break;
        char buf[3] = {hexStr[0], hexStr[1], 0};
        if(strlen(buf) < 2) break;
        pattern.push_back((uint8_t)strtoul(buf, NULL, 16));
        hexStr += 2;
    }
    if(pattern.empty()) return;

    for(auto& [base, size] : this->regions) {
        if(base < range.start) continue;
        if(base > range.end) break;

        uint64_t region_end = min(base + size, range.end);
        uint64_t region_base = max(base, range.start);
        uint64_t region_size = region_end - region_base;
        if(region_size < pattern.size()) continue;

        bool remapped = false;
        uint64_t loadSize = region_size;
        void* buffer = loadRegion(region_base, &loadSize, &remapped);
        if(!buffer) continue;

        uint8_t* bytes = (uint8_t*)buffer;
        uint64_t scanSize = min((uint64_t)loadSize, region_size);

        for(uint64_t off = 0; off <= scanSize - pattern.size(); off++) {
            bool match = true;
            for(size_t i = 0; i < pattern.size(); i++) {
                if(bytes[off + i] != pattern[i]) { match = false; break; }
            }
            if(match) {
                auto* rr = new result_region(region_base, pattern.size());
                rr->slides.push_back((uint32_t)(off));
                rr->types.push_back(JJ_Search_Type_UByte);
                result->regions.push_back(rr);
                result->count++;
            }
        }

        unloadRegion(buffer, loadSize, remapped);
    }

    firstScanDone = true;
    saveSnapshot();
}

void JJMemoryEngine::saveSnapshot() {
    snapshot.clear();
    for(auto* region : this->result->regions) {
        bool hasTypes = region->types.size() > 0;
        for(int j = 0; j < region->slides.size(); j++) {
            uint64_t address = region->region_base + region->slides[j];
            uint8_t type = hasTypes ? region->types[j] : this->lastNumberType;
            int len = JJ_Search_Type_Len[type];
            uint64_t value = 0;
            if(readMemory(&value, address, len)) {
                snapshot[address] = {type, value};
            }
        }
    }
}

void JJMemoryEngine::JJRefineByChange(int changeType) {
    size_t newCount = 0;

    for(int i = 0; i < this->result->regions.size(); i++) {
        result_region* region = this->result->regions[i];

        result_region* newRegion = nullptr;
        bool hasTypes = region->types.size() > 0;

        bool remapped = false;
        uint64_t mapsize = region->region_size;
        void* buffer = loadRegion(region->region_base, &mapsize, &remapped);

        if(buffer) {
            for(int j = 0; j < region->slides.size(); j++) {
                uint64_t address = region->region_base + region->slides[j];
                uint8_t type = hasTypes ? region->types[j] : this->lastNumberType;
                int len = JJ_Search_Type_Len[type];

                auto it = snapshot.find(address);
                if(it == snapshot.end()) continue;

                uint64_t snapValue = it->second.second;
                uint8_t snapType = it->second.first;

                uint64_t curValue = 0;
                if(!readMemory(&curValue, address, len)) continue;

                bool sameBits = (memcmp(&curValue, &snapValue, min((size_t)len, sizeof(uint64_t))) == 0);
                bool keep = false;

                switch(changeType) {
                    case JJ_Change_Unchanged:
                        keep = sameBits;
                        break;
                    case JJ_Change_Changed:
                        keep = !sameBits;
                        break;
                    case JJ_Change_Increased:
                    case JJ_Change_Decreased:
                        if(!sameBits && snapType == type) {
                            switch(type) {
                                case JJ_Search_Type_SByte: {
                                    int8_t c = (int8_t)curValue, s = (int8_t)snapValue;
                                    keep = (changeType == JJ_Change_Increased) ? (c > s) : (c < s);
                                    break;
                                }
                                case JJ_Search_Type_UByte: {
                                    uint8_t c = (uint8_t)curValue, s = (uint8_t)snapValue;
                                    keep = (changeType == JJ_Change_Increased) ? (c > s) : (c < s);
                                    break;
                                }
                                case JJ_Search_Type_SShort: {
                                    int16_t c = (int16_t)curValue, s = (int16_t)snapValue;
                                    keep = (changeType == JJ_Change_Increased) ? (c > s) : (c < s);
                                    break;
                                }
                                case JJ_Search_Type_UShort: {
                                    uint16_t c = (uint16_t)curValue, s = (uint16_t)snapValue;
                                    keep = (changeType == JJ_Change_Increased) ? (c > s) : (c < s);
                                    break;
                                }
                                case JJ_Search_Type_SInt: {
                                    int32_t c = (int32_t)curValue, s = (int32_t)snapValue;
                                    keep = (changeType == JJ_Change_Increased) ? (c > s) : (c < s);
                                    break;
                                }
                                case JJ_Search_Type_UInt: {
                                    uint32_t c = (uint32_t)curValue, s = (uint32_t)snapValue;
                                    keep = (changeType == JJ_Change_Increased) ? (c > s) : (c < s);
                                    break;
                                }
                                case JJ_Search_Type_SLong: {
                                    int64_t c = (int64_t)curValue, s = (int64_t)snapValue;
                                    keep = (changeType == JJ_Change_Increased) ? (c > s) : (c < s);
                                    break;
                                }
                                case JJ_Search_Type_ULong: {
                                    uint64_t c = curValue, s = snapValue;
                                    keep = (changeType == JJ_Change_Increased) ? (c > s) : (c < s);
                                    break;
                                }
                                case JJ_Search_Type_Float: {
                                    float c, s;
                                    memcpy(&c, &curValue, sizeof(float));
                                    memcpy(&s, &snapValue, sizeof(float));
                                    keep = (changeType == JJ_Change_Increased) ? (c > s) : (c < s);
                                    break;
                                }
                                case JJ_Search_Type_Double: {
                                    double c, s;
                                    memcpy(&c, &curValue, sizeof(double));
                                    memcpy(&s, &snapValue, sizeof(double));
                                    keep = (changeType == JJ_Change_Increased) ? (c > s) : (c < s);
                                    break;
                                }
                            }
                        }
                        break;
                }

                if(keep) {
                    if(!newRegion)
                        newRegion = new result_region(region->region_base, region->region_size);
                    newRegion->slides.push_back(region->slides[j]);
                    if(hasTypes) newRegion->types.push_back(region->types[j]);
                    newCount++;
                }
            }
        }

        unloadRegion(buffer, mapsize, remapped);

        delete this->result->regions[i];
        this->result->regions[i] = newRegion;
        if(newRegion) {
            newRegion->slides.shrink_to_fit();
            if(newRegion->types.size()) newRegion->types.shrink_to_fit();
        }
    }

    this->result->regions.erase(
        remove(this->result->regions.begin(), this->result->regions.end(), (result_region*)nullptr),
        this->result->regions.end());
    this->result->regions.shrink_to_fit();
    this->result->count = newCount;

    saveSnapshot();
}

void JJMemoryEngine::JJNearBySearch(size_t range, void *target, int type) {
    if(type <= 0 || type >= JJ_Search_Type_Max) return;

    int len = JJ_Search_Type_Len[type];

    size_t newCount = 0;

    range -= range % len;
    range += len;

    for(int i = 0; i < this->result->regions.size(); i++) {
        result_region* region = this->result->regions[i];

        bool hasType = region->types.size() > 0;
        bool needType = hasType || type != this->lastNumberType;

        NSLog(@"handle region [%d/%zu] %p,%zx : %zu", i, this->result->regions.size(),
              (void*)region->region_base, region->region_size, region->slides.size());

        result_region* newRegion = nullptr;

        int lastold = 0;
        long lastpos = 0;

        bool remapped = false;
        uint64_t mapsize = region->region_size;
        void* buffer = loadRegion(region->region_base, &mapsize, &remapped);

        if(buffer) {
            for(int j = 0; j < region->slides.size(); j++) {
                map<uint32_t, int8_t> matched;

                uint32_t curslide = region->slides[j];
                long rstart = (long)curslide - (long)range;
                long rend = (long)curslide + (long)range;

                if(rstart < 0) rstart = 0;
                if(rend > (long)region->region_size) rend = (long)region->region_size;

                if(lastpos > rstart)
                    rstart = lastpos;

                lastpos = rend;

                uint64_t data = (uint64_t)buffer + rstart;
                size_t size = (size_t)(rend - rstart);

                int foundcount = 0;
                uint32_t foundfirst = 0;
                uint32_t foundlast = 0;

                uint64_t pcurdata = data;
                uint64_t left_size = size;
                while(left_size >= (uint64_t)len) {
                    uint64_t pfound = ScanData(pcurdata, left_size, target, type);
                    if(!pfound) break;

                    uint32_t slide = (uint32_t)(pfound - (uint64_t)buffer);

                    matched[slide] = type;

                    if(foundcount == 0) foundfirst = slide;
                    foundlast = slide;
                    foundcount++;

                    pcurdata = pfound + len;
                    left_size = data + size - pcurdata;
                }

                if(foundcount) {
                    for(int o = lastold; o < region->slides.size(); o++) {
                        uint32_t oldslide = region->slides[o];

                        long first_down = (long)foundfirst - (long)range;
                        long first_up = (long)foundfirst + (long)range;
                        long last_down = (long)foundlast - (long)range;
                        long last_up = (long)foundlast + (long)range;

                        if((oldslide > first_down && oldslide < first_up) ||
                           (oldslide > last_down && oldslide < last_up)) {
                            matched[oldslide] = hasType ? region->types[o] : this->lastNumberType;
                            lastold = o + 1;
                        }
                    }
                }

                if(matched.size()) {
                    if(!newRegion)
                        newRegion = new result_region(region->region_base, region->region_size);

                    for(auto& [slide, slideType] : matched) {
                        newRegion->slides.push_back(slide);
                        if(needType) newRegion->types.push_back(slideType);
                    }

                    newCount += matched.size();
                }
            }
        } else {
            NSLog(@"read mem failed! [%d] %p %zx", i, (void*)region->region_base, region->region_size);
        }

        unloadRegion(buffer, mapsize, remapped);

        delete this->result->regions[i];
        this->result->regions[i] = newRegion;
        if(newRegion) {
            newRegion->slides.shrink_to_fit();
            newRegion->types.shrink_to_fit();
        }
    }

    this->result->regions.erase(
        remove(this->result->regions.begin(), this->result->regions.end(), (result_region*)nullptr),
        this->result->regions.end());

    this->result->regions.shrink_to_fit();
    this->result->count = newCount;
}

bool JJMemoryEngine::JJReadMemory(void* buf, uint64_t addr, int type) {
    if(type <= 0 || type >= JJ_Search_Type_Max) return false;

    int len = JJ_Search_Type_Len[type];
    return readMemory(buf, addr, len);
}

bool JJMemoryEngine::JJWriteMemory(void* address, void *target, int type) {
    if(type <= 0 || type >= JJ_Search_Type_Max) return false;

    int len = JJ_Search_Type_Len[type];

    mach_port_t object_name;
    mach_vm_size_t region_size = 0;
    mach_vm_address_t region_base = (uint64_t)address;

    vm_region_basic_info_data_64_t info = {};
    mach_msg_type_number_t info_cnt = VM_REGION_BASIC_INFO_COUNT_64;

    kern_return_t kr = mach_vm_region(this->task, &region_base, &region_size,
                                      VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info, &info_cnt, &object_name);
    if(kr != KERN_SUCCESS) {
        NSLog(@"mach_vm_region failed! %p", (void*)region_base);
        return false;
    }

    vm_address_t base = 0;
    if(!(info.protection & VM_PROT_WRITE)) {
        NSLog(@"unwritable region %p %llx : %x", (void*)region_base, (unsigned long long)region_size, info.protection);
        base = (uint64_t)address & ~PAGE_MASK;
        kr = mach_vm_protect(this->task, base, PAGE_SIZE, false, info.protection | VM_PROT_WRITE | VM_PROT_COPY);
        if(kr != KERN_SUCCESS) {
            NSLog(@"vm_protect failed! kr=%d [%p %lx] : %x", kr, (void*)base, (unsigned long)PAGE_SIZE, info.protection);
            kr = mach_vm_protect(this->task, base, PAGE_SIZE, false, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
            if(kr != KERN_SUCCESS) {
                NSLog(@"vm_protect failed2! kr=%d [%p %lx] : %x", kr, (void*)base, (unsigned long)PAGE_SIZE, info.protection);
                return false;
            }
        }
    }

    bool result = writeMemory(address, target, len);

    if(!result && base) {
        kr = mach_vm_protect(this->task, base, PAGE_SIZE, false, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
        if(kr != KERN_SUCCESS) {
            NSLog(@"vm_protect again failed! kr=%d [%p %lx] : %x", kr, (void*)base, (unsigned long)PAGE_SIZE, info.protection);
        } else {
            result = writeMemory(address, target, len);
        }
    }

    if(base)
        vm_protect(this->task, base, PAGE_SIZE, false, info.protection);

    return result;
}

int JJMemoryEngine::JJWriteAll(void *target, int type) {
    if(type <= 0 || type >= JJ_Search_Type_Max) return 0;

    int len = JJ_Search_Type_Len[type];

    int count = 0;
    for(auto* region : this->result->regions) {
        for(auto slide : region->slides) {
            uint64_t address = region->region_base + slide;
            if(writeMemory((void*)address, target, len))
                count++;
        }
    }
    return count;
}

vector<pair<uint64_t, uint64_t>> JJMemoryEngine::JJFindPointers(uint64_t targetAddr, AddrRange range) {
    vector<pair<uint64_t, uint64_t>> results;

    for(auto& [base, size] : this->regions) {
        if(base < range.start || base > range.end) continue;

        uint64_t region_end = min(base + size, range.end);
        uint64_t region_base = max(base, range.start);
        uint64_t region_size = region_end - region_base;
        if(region_size < 8) continue;

        bool remapped = false;
        uint64_t loadSize = 0;
        void* buffer = loadRegion(region_base, &loadSize, &remapped);
        if(!buffer) continue;

        uint64_t* ptrs = (uint64_t*)buffer;
        uint64_t scanSize = min((uint64_t)loadSize, region_size) / 8;

        for(uint64_t i = 0; i < scanSize; i++) {
            if(ptrs[i] == targetAddr) {
                results.push_back({region_base + i * 8, ptrs[i]});
            }
        }

        unloadRegion(buffer, loadSize, remapped);
    }

    return results;
}

size_t JJMemoryEngine::getResultsCount() {
    return this->result->count;
}

vector<void*> JJMemoryEngine::getResults(size_t count, size_t skip) {
    vector<void*> results;
    int index = 0;
    for(auto* region : this->result->regions) {
        if((index + (int)region->slides.size()) <= (int)skip) {
            index += (int)region->slides.size();
            continue;
        }
        for(auto slide : region->slides) {
            if(index >= (int)skip && (index - (int)skip) < (int)count) {
                uint64_t address = region->region_base + slide;
                results.push_back((void*)address);
            }
            index++;
        }
    }
    return results;
}

map<void*, int8_t> JJMemoryEngine::getResultsAndTypes(int count, int skip) {
    map<void*, int8_t> results;
    int index = 0;
    for(auto* region : this->result->regions) {
        auto hasTypes = region->types.size();
        if((index + (int)region->slides.size()) <= skip) {
            index += (int)region->slides.size();
            continue;
        }
        for(int j = 0; j < (int)region->slides.size(); j++) {
            if(index >= skip && (index - skip) < count) {
                uint64_t address = region->region_base + region->slides[j];
                results[(void*)address] = hasTypes ? region->types[j] : 0;
            }
            index++;
        }
    }
    return results;
}
