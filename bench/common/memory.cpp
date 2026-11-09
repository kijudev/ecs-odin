#include "memory.hpp"

#include <algorithm>
#include <cstdlib>
#include <malloc.h>
#include <new>

namespace bench::memory {

namespace {

std::size_t live_bytes = 0;
std::size_t peak_bytes = 0;

void *track(void *ptr) {
    if (ptr) {
        live_bytes += malloc_usable_size(ptr);
        peak_bytes = std::max(peak_bytes, live_bytes);
    }
    return ptr;
}

void untrack(void *ptr) {
    if (ptr) live_bytes -= malloc_usable_size(ptr);
}

} // namespace

std::size_t live() { return live_bytes; }
std::size_t peak() { return peak_bytes; }
void reset_peak() { peak_bytes = live_bytes; }

void *alloc(std::size_t size) { return track(std::malloc(size)); }

void *alloc_zeroed(std::size_t count, std::size_t size) { return track(std::calloc(count, size)); }

void *alloc_aligned(std::size_t align, std::size_t size) {
    // aligned_alloc wants the size to be a multiple of the alignment.
    return track(std::aligned_alloc(align, (size + align - 1) / align * align));
}

void *resize(void *ptr, std::size_t size) {
    untrack(ptr);
    void *moved = std::realloc(ptr, size);
    return track(moved || size == 0 ? moved : ptr);
}

void free(void *ptr) {
    untrack(ptr);
    std::free(ptr);
}

} // namespace bench::memory

// >---------------------------------------------------- Global operator new/delete

void *operator new(std::size_t size) {
    if (void *ptr = bench::memory::alloc(size ? size : 1)) return ptr;
    throw std::bad_alloc();
}

void *operator new(std::size_t size, std::align_val_t align) {
    if (void *ptr = bench::memory::alloc_aligned(std::size_t(align), size ? size : 1)) return ptr;
    throw std::bad_alloc();
}

void *operator new[](std::size_t size) { return operator new(size); }
void *operator new[](std::size_t size, std::align_val_t align) { return operator new(size, align); }

void operator delete(void *ptr) noexcept { bench::memory::free(ptr); }
void operator delete[](void *ptr) noexcept { bench::memory::free(ptr); }
void operator delete(void *ptr, std::size_t) noexcept { bench::memory::free(ptr); }
void operator delete[](void *ptr, std::size_t) noexcept { bench::memory::free(ptr); }
void operator delete(void *ptr, std::align_val_t) noexcept { bench::memory::free(ptr); }
void operator delete[](void *ptr, std::align_val_t) noexcept { bench::memory::free(ptr); }
void operator delete(void *ptr, std::size_t, std::align_val_t) noexcept {
    bench::memory::free(ptr);
}
void operator delete[](void *ptr, std::size_t, std::align_val_t) noexcept {
    bench::memory::free(ptr);
}
