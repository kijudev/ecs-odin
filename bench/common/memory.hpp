// Allocation counting. memory.cpp routes the global operator new/delete through here, and the
// flecs binary points its os api at these functions, so every byte a world holds is seen.
#pragma once

#include <cstddef>

namespace bench::memory {

std::size_t live();
std::size_t peak();

// Starts a new peak measurement from the current live bytes.
void reset_peak();

void *alloc(std::size_t size);
void *alloc_zeroed(std::size_t count, std::size_t size);
void *alloc_aligned(std::size_t align, std::size_t size);
void *resize(void *ptr, std::size_t size);
void free(void *ptr);

} // namespace bench::memory
