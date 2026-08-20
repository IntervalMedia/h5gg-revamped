#ifndef H5GG_TARGET_SESSION_H
#define H5GG_TARGET_SESSION_H

#include <mach/mach.h>
#include <sys/types.h>

class JJMemoryEngine;

using H5GGTaskPortReleaser = void (*)(mach_port_t port);
using H5GGMemoryEngineDeleter = void (*)(JJMemoryEngine* engine);

class TargetProcess {
public:
    TargetProcess();
    TargetProcess(pid_t pid,
                  mach_port_t port,
                  H5GGTaskPortReleaser releaser = nullptr);
    ~TargetProcess();

    TargetProcess(const TargetProcess&) = delete;
    TargetProcess& operator=(const TargetProcess&) = delete;
    TargetProcess(TargetProcess&& other) noexcept;
    TargetProcess& operator=(TargetProcess&& other) noexcept;

    pid_t pid() const;
    mach_port_t port() const;
    bool valid() const;
    bool ownsPort() const;
    void reset();

private:
    pid_t pid_;
    mach_port_t port_;
    H5GGTaskPortReleaser releaser_;
};

class MemorySession {
public:
    MemorySession(TargetProcess target,
                  JJMemoryEngine* engine,
                  H5GGMemoryEngineDeleter engineDeleter);
    ~MemorySession();

    MemorySession(const MemorySession&) = delete;
    MemorySession& operator=(const MemorySession&) = delete;

    const TargetProcess& target() const;
    JJMemoryEngine* engine() const;
    bool firstSearchDone() const;
    int lastSearchType() const;

    void markSearchDone(int type);
    void resetSearchState();
    void replaceEngine(JJMemoryEngine* engine,
                       H5GGMemoryEngineDeleter engineDeleter);

private:
    TargetProcess target_;
    JJMemoryEngine* engine_;
    H5GGMemoryEngineDeleter engineDeleter_;
    bool firstSearchDone_;
    int lastSearchType_;
};

#endif
