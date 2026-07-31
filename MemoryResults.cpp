#include "MemoryResults.h"

#include <algorithm>

result_region::result_region(uint64_t base, size_t size)
    : region_base(base), region_size(size) {}

bool result_region::append(uint32_t slide, int8_t type) {
    if((type == 0 && !types.empty()) ||
       (type != 0 && !slides.empty() && types.empty())) {
        return false;
    }

    slides.push_back(slide);
    if(type != 0) {
        types.push_back(type);
    }
    return true;
}

bool result_region::hasTypes() const {
    return !types.empty();
}

int8_t result_region::typeAt(size_t index, int8_t fallback) const {
    return hasTypes() && index < types.size() ? types[index] : fallback;
}

bool result_region::invariantHolds() const {
    return types.empty() || types.size() == slides.size();
}

Result::~Result() {
    clear();
}

void Result::add(std::unique_ptr<result_region> region) {
    if(!region || !region->invariantHolds()) {
        return;
    }
    resultCount += region->slides.size();
    regions.push_back(region.release());
}

void Result::replace(size_t index, std::unique_ptr<result_region> region) {
    if(index >= regions.size() || (region && !region->invariantHolds())) {
        return;
    }

    delete regions[index];
    regions[index] = region.release();
    recount();
}

void Result::removeEmptyRegions() {
    regions.erase(
        std::remove_if(regions.begin(), regions.end(), [](result_region* region) {
            if(!region || region->slides.empty()) {
                delete region;
                return true;
            }
            return false;
        }),
        regions.end());
    recount();
}

void Result::clear() {
    for(auto* region : regions) {
        delete region;
    }
    regions.clear();
    resultCount = 0;
}

void Result::recount() {
    resultCount = 0;
    for(const auto* region : regions) {
        if(region) {
            resultCount += region->slides.size();
        }
    }
}

size_t Result::count() const {
    return resultCount;
}

size_t Result::regionCount() const {
    return regions.size();
}

result_region* Result::regionAt(size_t index) {
    return index < regions.size() ? regions[index] : nullptr;
}

const std::vector<result_region*>& Result::allRegions() const {
    return regions;
}

bool Result::invariantHolds() const {
    size_t actualCount = 0;
    for(const auto* region : regions) {
        if(!region || !region->invariantHolds()) {
            return false;
        }
        actualCount += region->slides.size();
    }
    return actualCount == resultCount;
}
