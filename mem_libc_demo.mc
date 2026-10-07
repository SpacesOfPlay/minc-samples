// mem_libc_demo.mc: Swap the heap to libc malloc on linux.
//
// Linux x64 links libc.so.6, a NOP on other platforms.
// By default minc's own heap (lib/mem_heap.mc) is used.
//
import mem_libc;

when os(linux) && arch(x64) {
    extern "libc.so.6" u64 malloc_usable_size(void* p);
}

struct Node {
    i32 value;
    Node* next;
}

i32 main() {
    // Plain allocations.
    u8* buf = alloc<u8>(100);
    for i32 i = 0; i < 100; i++ { buf[i] = cast(u8, i); }
    buf = cast(u8*, realloc(buf, 4000));
    if buf[99] != 99 { return 1; }
    print("realloc kept {} bytes\n", 100);

    // new() zeroes above the allocator, whichever heap is in use.
    Node* head = null;
    for i32 i = 0; i < 5; i++ {
        Node* n = new(Node);
        n.value = i;
        n.next = head;
        head = n;
    }
    i32 sum = 0;
    for Node* n = head; n != null; n = n.next { sum = sum + n.value; }
    print("list sum {}\n", sum);

    // Strings and format allocate through the same heap.
    using string s = format("{} nodes, {} bytes in buf", 5, 4000);
    print("{}\n", s);

    when os(linux) && arch(x64) {
        // glibc reports the block it handed out: the request rounded up
        // to its own granularity, proof that libc owns these blocks.
        print("libc usable size of the 4000-byte block: {}\n", cast(i64, malloc_usable_size(buf)));
    }

    while head != null {
        Node* next = head.next;
        free(head);
        head = next;
    }
    free(buf);
    return 0;
}
