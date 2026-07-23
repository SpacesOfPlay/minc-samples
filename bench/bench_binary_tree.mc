// Binary search tree benchmark
// Inserts 500K random values, sums via inorder traversal, 5 iterations.

#include "bench_util.mc"

struct Node {
    i32 value;
    Node* left;
    Node* right;
}

Node* bst_insert(Node* root, i32 val) {
    if root == null {
        Node* n = new(Node);
        n.value = val;
        return n;
    }
    if val < root.value {
        root.left = bst_insert(root.left, val);
    } else {
        root.right = bst_insert(root.right, val);
    }
    return root;
}

i64 bst_sum(Node* root) {
    if root == null { return 0; }
    return bst_sum(root.left) + root.value + bst_sum(root.right);
}

void bst_free(Node* root) {
    if root == null { return; }
    bst_free(root.left);
    bst_free(root.right);
    free(root);
}

i64 run_tree(i32 n) {
    i64 state = 31337;
    Node* root = null;
    for i32 i = 0; i < n; i++ {
        state = state * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407;
        i32 val = cast(i32, (state >> 33) & 0x7FFFFFFF);
        root = bst_insert(root, val);
    }
    i64 result = bst_sum(root);
    bst_free(root);
    return result;
}

i32 main() {
    i32 n = 500_000;

    // Warm up
    i64 result = run_tree(n);

    i64 freq = qpf();
    i64 start = qpc();
    for i32 iter = 0; iter < 8; iter++ {
        result = run_tree(n);
    }
    i64 end = qpc();

    bench_print("binary_tree", result, elapsed_us(start, end, freq));
    return 0;
}
