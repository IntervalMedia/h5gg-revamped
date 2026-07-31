#ifndef JJ_Header_h
#define JJ_Header_h

#include <mach-o/dyld.h>
#include <mach/mach.h>
#include <sys/mman.h>
#include <stdio.h>
#include <unordered_map>
#include <vector>
#include <map>
#include <set>

#include "MemoryResults.h"
#include "MemoryValue.h"
#include "vmtag.h"

using namespace std;

extern "C" kern_return_t mach_vm_region
(
     vm_map_t target_task,
     mach_vm_address_t *address,
     mach_vm_size_t *size,
     vm_region_flavor_t flavor,
     vm_region_info_t info,
     mach_msg_type_number_t *infoCnt,
     mach_port_t *object_name
 );

extern "C" kern_return_t mach_vm_protect
(
 vm_map_t target_task,
 mach_vm_address_t address,
 mach_vm_size_t size,
 boolean_t set_maximum,
 vm_prot_t new_protection
 );

enum JJ_Change_Type {
    JJ_Change_Unchanged = 1,
    JJ_Change_Changed,
    JJ_Change_Increased,
    JJ_Change_Decreased,
};

struct AddrRange {
    uint64_t start;
    uint64_t end;
};

class JJMemoryEngine
{
    mach_port_t task;
    Result *result;
    map<uint64_t,uint64_t> regions;
    bool firstScanDone;
    float float_tolerance;
    int lastNumberType;

    void freeResults();
    size_t readMemoryBytes(void* buf, uint64_t addr, size_t len);
    bool readMemory(void* buf, uint64_t addr, size_t len);
    bool writeMemory(void* address, void *target, size_t len);

    uint64_t ScanData(uint64_t buffer, uint64_t size, void* target, int type);

    void* loadRegion(uint64_t base, uint64_t* psize, bool* remapped);
    void unloadRegion(void* buffer, uint64_t size, bool remapped);

    void ScanRegion(AddrRange range, uint64_t base, uint64_t size, void* target, int type, vector<result_region*>* outResults);
    void enumerateRegions(AddrRange range);
    void FirstScan(AddrRange range, void* target, int type);
    void ScanAgain(AddrRange range, void* target, int type);
    void saveSnapshot();

public:
    size_t JJFilterResults(const char* valueStr, int type, int mode);
    JJMemoryEngine(mach_port_t task);
    ~JJMemoryEngine();

    void SetFloatTolerance(float d);

    void JJScanMemory(AddrRange range, void* target, int type);
    void JJScanHexMemory(AddrRange range, const char* hexStr);
    void JJNearBySearch(size_t range, void *target, int type);
    vector<pair<uint64_t, uint64_t>> JJFindPointers(uint64_t targetAddr, AddrRange range);
    size_t JJReadBytes(void* buf, uint64_t addr, size_t len);
    bool JJReadMemory(void* buf, uint64_t addr, int type);
    bool JJWriteMemory(void* address, void *target, int type);
    int JJWriteAll(void *target, int type);

    size_t getResultsCount();
    vector<void*> getResults(size_t count, size_t skip = 0);
    map<void*, int8_t> getResultsAndTypes(int count, int skip = 0);

    void JJRefineByChange(int changeType);
    map<uint64_t, pair<uint8_t, uint64_t>> snapshot;
};

#endif /* JJ_Header_h */
