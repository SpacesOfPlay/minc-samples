// bench_list_sum.mc - shuffled linked list traversal (pointer-chasing latency, cache behavior)
#include "bench_util.mc"

struct ListNode {
    i32 value;
    ListNode* next;
}

ListNode* build_list(i32 n) {
    // Allocate all nodes in a contiguous block, then shuffle links
    ListNode* nodes = alloc<ListNode>(n);
    // Initialize values
    i64 state = 88888;
    for i32 i = 0; i < n; i++ {
        state = state * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407;
        (nodes + i).value = cast(i32, (state >> 33) & 0xFFFF);
        (nodes + i).next = null;
    }
    // Fisher-Yates shuffle to randomize traversal order
    // Use an index array to build random linked order
    i32* order = alloc<i32>(n);
    for i32 i = 0; i < n; i++ {
        order[i] = i;
    }
    state = 99999;
    for i32 i = n - 1; i > 0; i-- {
        state = state * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407;
        i32 j = cast(i32, cast(u64, state >> 33) % cast(u64, i + 1));
        // Swap order[i] and order[j]
        i32 tmp = order[i];
        order[i] = order[j];
        order[j] = tmp;
    }
    // Link nodes in shuffled order
    for i32 i = 0; i < n - 1; i++ {
        (nodes + order[i]).next = nodes + order[i + 1];
    }
    ListNode* head = nodes + order[0];
    free(order);
    return head;
}

i64 list_sum(ListNode* head) {
    i64 sum = 0;
    ListNode* cur = head;
    while cur != null {
        sum = sum + cur.value;
        cur = cur.next;
    }
    return sum;
}

i32 main() {
    i32 n = 1_000_000;
    ListNode* head = build_list(n);

    // Warm up
    i64 result = list_sum(head);

    i64 freq = qpf();
    i64 start = qpc();
    for i32 iter = 0; iter < 200; iter++ {
        result = list_sum(head);
    }
    i64 end = qpc();

    bench_print("list_sum", result, elapsed_us(start, end, freq));
    return 0;
}
