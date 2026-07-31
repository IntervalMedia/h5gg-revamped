#include "MemoryFilter.h"

#include "MemoryValue.h"

#include <memory>

size_t JJFilterResultSet(Result& results,
                         const char* value,
                         int type,
                         int mode,
                         const JJMemoryReader& reader) {
    uint8_t target[8] = {0};
    if(!reader ||
       type <= JJ_Search_Type_Error || type >= JJ_Search_Type_Max ||
       (mode != JJ_Filter_Equal && mode != JJ_Filter_Greater && mode != JJ_Filter_Less) ||
       !JJParseValue(value, type, target)) {
        return 0;
    }

    size_t valueLength = JJ_Search_Type_Len[type];
    size_t regionCount = results.regionCount();
    for(size_t regionIndex = 0; regionIndex < regionCount; regionIndex++) {
        result_region* region = results.regionAt(regionIndex);
        auto filtered = std::make_unique<result_region>(region->region_base, region->region_size);

        for(size_t slideIndex = 0; slideIndex < region->slides.size(); slideIndex++) {
            uint64_t address = region->region_base + region->slides[slideIndex];
            uint8_t current[8] = {0};
            if(reader(current, address, valueLength) &&
               JJValueMatchesFilter(current, target, type, mode)) {
                filtered->append(region->slides[slideIndex], type);
            }
        }

        results.replace(regionIndex, std::move(filtered));
    }

    results.removeEmptyRegions();
    return results.count();
}
