#ifndef H5GG_MODAL_REQUEST_QUEUE_H
#define H5GG_MODAL_REQUEST_QUEUE_H

#include <memory>

class ModalRequestQueue {
private:
    struct Coordinator;
    struct State;

public:
    class Request {
    public:
        ~Request();

        Request(const Request&) = delete;
        Request& operator=(const Request&) = delete;
        Request(Request&& other) noexcept;
        Request& operator=(Request&& other) noexcept;

        bool active() const;
        bool completed() const;
        void waitUntilActive() const;
        void waitUntilCompleted() const;
        bool complete();

    private:
        friend class ModalRequestQueue;
        Request(std::shared_ptr<Coordinator> coordinator,
                std::shared_ptr<State> state);
        void cancel();

        std::shared_ptr<Coordinator> coordinator_;
        std::shared_ptr<State> state_;
    };

    ModalRequestQueue();
    Request enqueue();

private:
    std::shared_ptr<Coordinator> coordinator_;
};

#endif
