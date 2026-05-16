#pragma once
#ifndef BENTO_H
#define BENTO_H

#define BT_VERSION_MAJOR 1
#define BT_VERSION_MINOR 0
#define BT_VERSION_PATCH 0

// Version is 0xMMmmPPPP
#define BT_LIB_VERSION(M, m, p) (((M & 0xFF) << 24) | ((m & 0xFF) << 16) | (p & 0xFFFF))

#define BT_STR(x)                   #x
#define BT_XSTR(x)                  BT_STR(x)
#define BT_LIB_VERSION_STR(M, m, p) BT_XSTR(M) "." BT_XSTR(m) "." BT_XSTR(p)

#define BT_VERSION     BT_LIB_VERSION(BT_VERSION_MAJOR, BT_VERSION_MINOR, BT_VERSION_PATCH)
#define BT_VERSION_STR BT_LIB_VERSION_STR(BT_VERSION_MAJOR, BT_VERSION_MINOR, BT_VERSION_PATCH)

// Function specifiers for when the library is built and used as a shared library
// https://gcc.gnu.org/wiki/Visibility
#if defined(_WIN32) || defined(__CYGWIN__)
    #if defined(__TINYC__)
        #define __declspec(x) __attribute__((x))
    #endif
    #define BT_DLL_IMPORT __declspec(dllimport)
    #define BT_DLL_EXPORT __declspec(dllexport)
    #define BT_DLL_LOCAL
#else
    // Note: visibility("default") exposes the symbol for dynamic linkage when compiled with -fvisibility=hidden
    #define BT_DLL_IMPORT __attribute__((visibility("default")))
    #define BT_DLL_EXPORT __attribute__((visibility("default")))
    #define BT_DLL_LOCAL  __attribute__((visibility("hidden")))
#endif

#ifdef BT_DLL // Defined if library is compiled as a DLL
    #ifdef BT_DLL_BUILD // Defined if we are building the DLL (instead of using it)
        #define BT_API BT_DLL_EXPORT
    #else
        #define BT_API BT_DLL_IMPORT
    #endif
    #define BT_LOCAL BT_DLL_LOCAL
#else // BT_DLL is not defined: this is a static library
    #define BT_API
    #define BT_LOCAL static
#endif

#ifdef __cplusplus
    #define BT_LITERAL(T, ...) T{ __VA_ARGS__ }
#else
    #define BT_LITERAL(T, ...) (T){ __VA_ARGS__ }
#endif

#ifdef __cplusplus
extern "C" {
#endif

#include <stdbool.h>
#include <stdint.h>

#ifndef BT_MAX_NUM_LAYOUT_ELEMENTS
#define BT_MAX_NUM_LAYOUT_ELEMENTS 64
#endif

// Determines along which axis the element's children are laid out
typedef enum BtLayoutDir
{
    BT_LAYOUT_DIR_LEFT_TO_RIGHT = 0,
    BT_LAYOUT_DIR_TOP_TO_BOTTOM
} BtLayoutDir;

// Determines how an element's preferred size (flex-basis) is computed
typedef enum BtBasis
{
    BT_BASIS_AUTO = 0, // Content-based (wrap children)
    BT_BASIS_FIXED,    // Explicit size in pixels
    BT_BASIS_PERCENT   // Fraction [0,1] of parent available size
} BtBasis;

// Per-side padding values
typedef struct BtPadding
{
    uint16_t l; // Left   padding in pixels
    uint16_t r; // Right  padding in pixels
    uint16_t b; // Bottom padding in pixels
    uint16_t t; // Top    padding in pixels
} BtPadding;

// Sizing policy for one axis
typedef struct BtAxisSizing
{
    BtBasis basis; // How the preferred size (flex-basis) is computed

    union
    {
        float fixed;   // Preferred size in pixels (when basis == BT_BASIS_FIXED)
        float percent; // Preferred size as fraction [0,1] of parent (when basis == BT_BASIS_PERCENT)
    } value;

    struct
    {
        float min; // Minimum allowed size in pixels
        float max; // Maximum and maximum size in pixels (0 means no constraint)
    } min_max;

    float grow;   // Weight for underflow distribution (>=0, 0 means don't grow)
    float shrink; // Weight for overflow  distribution (>=0, 0 means don't shrink)
} BtAxisSizing;

// Configuration for a layout element
typedef struct BtLayoutElementDesc
{
    BtLayoutDir  layout_dir; // Direction along which the child elements are laid out
    BtPadding    padding; // Per-side padding
    uint16_t     child_gap; // Space in pixels between child elements along the layout axis
    uint8_t      splitter_hit_area_padding; // Extra pixels on each side for splitter drag/hover detection (does not affect layout)
    uint8_t      pad0_;
    BtAxisSizing sizing_w; // Controls how the width  of the element is defined
    BtAxisSizing sizing_h; // Controls how the height of the element is defined
    void *       userdata; // User data attached to the layout element
} BtLayoutElementDesc;

typedef struct BtLayoutElement BtLayoutElement;

// Intrusive tree pointers linking an element to its parent, children and siblings
typedef struct BtLayoutElementLinks
{
    BtLayoutElement * parent;
    BtLayoutElement * first_child;
    BtLayoutElement * prev_sibling;
    BtLayoutElement * next_sibling;
} BtLayoutElementLinks;

// Layout element type
typedef enum BtLayoutElementType
{
    BT_LAYOUT_ELEMENT_TYPE_BOX = 0, // Default element type: a box
    BT_LAYOUT_ELEMENT_TYPE_SPLITTER // Resize splitter
} BtLayoutElementType;

// Node in the layout tree
struct BtLayoutElement
{
    BtLayoutElementType type; // Type of the layout element

    float x; // Position along the X-axis
    float y; // Position along the Y-axis
    float w; // Width
    float h; // Height

    float min_w; // Element intrinsic width
    float min_h; // Element intrinsic height

    uint8_t pad0_[4];

    BtLayoutElementDesc desc; // Element configuration

    BtLayoutElementLinks links; // Intrusive tree pointers
};

// Global layout settings
typedef struct BtLayoutConfig
{
    float grid_snapping; // Snap grid size in pixels (0: 1px snapping | < 0: disabled)
} BtLayoutConfig;

// Fixed-capacity flat array used as a stack or queue of layout element pointers
typedef struct BtLayoutElementBuffer
{
    BtLayoutElement * data[BT_MAX_NUM_LAYOUT_ELEMENTS];
    int               count;
    uint8_t           pad0_[4];
} BtLayoutElementBuffer;

// Transient context used during the tree-building setup phase
typedef struct BtLayoutSetupContext
{
    BtLayoutElementBuffer layout_elements_stack;
} BtLayoutSetupContext;

// Transient context used during the multi-pass layout computation phase
typedef struct BtLayoutBuildContext
{
    // Each field corresponds to one layout pass: since passes don't overlap so they can share memory
    union
    {
        struct // Buffers used during the "compute intrinsic sizes" phase
        {
            BtLayoutElementBuffer dfs_stack_0; // DFS traversal order
            BtLayoutElementBuffer dfs_stack_1; // DFS post-order result
        } intrinsic_sizes;
        struct // Buffers used during the "size containers along axis" phase
        {
            BtLayoutElementBuffer bfs_buffer;
            BtLayoutElementBuffer resizable_containers;
        } size_axis;
        struct // Buffers used during the "position childen" phase
        {
            BtLayoutElementBuffer stack;
        } position_children;
    } phases;
} BtLayoutBuildContext;

// Snapshot of mouse state used to compute interactions with the layout tree elements
typedef struct BtMouseInputs
{
    float    pos_x;
    float    pos_y;
    float    delta_x;
    float    delta_y;
    uint32_t pressed  : 1; // MB went down this frame
    uint32_t held     : 1; // MB currently held
    uint32_t released : 1; // MB went up this frame
    uint32_t pad0_    : 29;
} BtMouseInputs;

// Tracks which splitter element is hovered or being dragged
typedef struct BtSplitterState
{
    BtLayoutElement * active_splitter; // Pointer to the active splitter (hovered or dragged)
    uint8_t           hovered : 1; // Splitter is being hovered
    uint8_t           dragged : 1; // Splitter is being dragged
    uint8_t           pad0_   : 6;
    uint8_t           pad1_[7];
} BtSplitterState;

// Layout setup
BT_API void                  bt_begin_layout(BtLayoutSetupContext * ctx);
BT_API void                  bt_end_layout(BtLayoutSetupContext * ctx);
BT_API BtLayoutElementDesc * bt_begin_layout_element(BtLayoutSetupContext * ctx, BtLayoutElement * layout_element);
BT_API void                  bt_end_layout_element(BtLayoutSetupContext * ctx);
BT_API void                  bt_splitter(BtLayoutSetupContext * ctx, BtLayoutElement * splitter, float size, uint8_t hit_area_padding);

// Layout update
BT_API void bt_compute_layout(
    const BtLayoutConfig * config,
    BtLayoutBuildContext * ctx,
    BtLayoutElement *      root,
    float                  root_x,
    float                  root_y,
    float                  root_w,
    float                  root_h
);

BT_API bool bt_process_splitter_interactions(
    const BtLayoutConfig * config,
    BtLayoutBuildContext * ctx,
    BtSplitterState *      splitter_state,
    BtLayoutElement *      root,
    const BtMouseInputs *  mouse_inputs
);

BT_API void bt_clear_layout_element_links(BtLayoutElement * layout_element);

// Layout query
BT_API bool bt_can_splitter_resize(const BtLayoutConfig * config, const BtLayoutElement * splitter, float delta);

#ifdef __cplusplus
}
#endif

#ifdef BT_IMPLEMENTATION

#ifndef BT_ASSERT
#include <assert.h>
#define BT_ASSERT(x) assert(x)
#endif

#include <float.h> // FLT_MAX
#include <math.h>

#define BT_EPSILON 0.0001f

BT_LOCAL void bt__stack_clear(BtLayoutElementBuffer * buf)
{
    buf->count = 0;
}

BT_LOCAL void bt__stack_push(BtLayoutElementBuffer * buf, BtLayoutElement * e)
{
    BT_ASSERT(buf->count < BT_MAX_NUM_LAYOUT_ELEMENTS);
    buf->data[buf->count++] = e;
}

BT_LOCAL BtLayoutElement * bt__stack_pop(BtLayoutElementBuffer * buf)
{
    BT_ASSERT(buf->count > 0);
    return buf->data[--buf->count];
}

BT_LOCAL BtLayoutElement * bt__stack_peek(const BtLayoutElementBuffer * buf)
{
    BT_ASSERT(buf->count > 0);
    return buf->data[buf->count - 1];
}

BT_LOCAL bool bt__stack_is_empty(const BtLayoutElementBuffer * buf)
{
    return buf->count == 0;
}

BT_LOCAL void bt__array_clear(BtLayoutElementBuffer * buf)
{
    buf->count = 0;
}

BT_LOCAL void bt__array_add(BtLayoutElementBuffer * buf, BtLayoutElement * e)
{
    BT_ASSERT(buf->count < BT_MAX_NUM_LAYOUT_ELEMENTS);
    buf->data[buf->count++] = e;
}

BT_LOCAL BtLayoutElement * bt__array_remove_swap_back(BtLayoutElementBuffer * buf, int idx)
{
    BT_ASSERT(buf->count > 0);
    BtLayoutElement * removed = buf->data[idx];
    buf->data[idx]            = buf->data[--buf->count];
    return removed;
}

BT_API void bt_begin_layout(BtLayoutSetupContext * ctx)
{
    bt__stack_clear(&ctx->layout_elements_stack);
    bt__stack_push(&ctx->layout_elements_stack, NULL);
}

BT_API void bt_end_layout(BtLayoutSetupContext * ctx)
{
    (void)ctx;
    BT_ASSERT(ctx->layout_elements_stack.count == 1); // Error: unmatched bt_end_layout_element calls
}

BT_LOCAL void bt__add_child_layout_element_to_parent(BtLayoutElement * layout_element, BtLayoutElement * parent)
{
    // Error: layout element already inserted
    BT_ASSERT(layout_element->links.parent == NULL);
    BT_ASSERT(layout_element->links.first_child == NULL);
    BT_ASSERT(layout_element->links.prev_sibling == NULL);
    BT_ASSERT(layout_element->links.next_sibling == NULL);

    layout_element->links.parent = parent;

    BtLayoutElement ** last_child = &parent->links.first_child;
    BtLayoutElement *  prev_child = NULL;
    while(*last_child)
    {
        prev_child = *last_child;
        last_child = &((*last_child)->links.next_sibling);
    }

    (*last_child)                      = layout_element;
    layout_element->links.prev_sibling = prev_child;
}

BT_API BtLayoutElementDesc * bt_begin_layout_element(BtLayoutSetupContext * ctx, BtLayoutElement * layout_element)
{
    if(!ctx || !layout_element)
        return NULL;

    if(ctx->layout_elements_stack.count < BT_MAX_NUM_LAYOUT_ELEMENTS)
    {
        layout_element->type = BT_LAYOUT_ELEMENT_TYPE_BOX;

        BtLayoutElement * parent = bt__stack_peek(&ctx->layout_elements_stack);
        if(parent)
            bt__add_child_layout_element_to_parent(layout_element, parent);

        bt__stack_push(&ctx->layout_elements_stack, layout_element);
        return &layout_element->desc;
    }
    return NULL;
}

// Note: assumes that the parent layout direction has been setup
BT_API void bt_splitter(BtLayoutSetupContext * ctx, BtLayoutElement * splitter, float size, uint8_t hit_area_padding)
{
    BtLayoutElementDesc * desc = bt_begin_layout_element(ctx, splitter);
    if(desc)
    {
        splitter->type = BT_LAYOUT_ELEMENT_TYPE_SPLITTER;

        if(splitter->links.parent->desc.layout_dir == BT_LAYOUT_DIR_LEFT_TO_RIGHT)
        {
            desc->sizing_w = BT_LITERAL(BtAxisSizing, .basis = BT_BASIS_FIXED, .value = { .fixed = size });
            desc->sizing_h = BT_LITERAL(BtAxisSizing, .basis = BT_BASIS_AUTO, .grow = 1.f);
        }
        else
        {
            desc->sizing_w = BT_LITERAL(BtAxisSizing, .basis = BT_BASIS_AUTO, .grow = 1.f);
            desc->sizing_h = BT_LITERAL(BtAxisSizing, .basis = BT_BASIS_FIXED, .value = { .fixed = size });
        }
        desc->splitter_hit_area_padding = hit_area_padding;

        bt_end_layout_element(ctx);
    }
}

BT_API void bt_end_layout_element(BtLayoutSetupContext * ctx)
{
    // Error: bt_end_layout_element without a corresponding bt_begin_layout_element
    BT_ASSERT(ctx->layout_elements_stack.count > 1);

    if(ctx->layout_elements_stack.count > 1)
        bt__stack_pop(&ctx->layout_elements_stack);
}

// ==========================================================
// Utilities
// ==========================================================

BT_LOCAL float bt__clamp(float v, float min, float max)
{
    return v < min ? min : v > max ? max : v;
}

BT_LOCAL float bt__get_snap(const BtLayoutConfig * config)
{
    return config->grid_snapping > 0 ? config->grid_snapping : 1.f;
}

BT_LOCAL float bt__snap_to_grid(const BtLayoutConfig * config, float v)
{
    const float snap = bt__get_snap(config);
    return roundf(v / snap) * snap;
}

BT_LOCAL float * bt__get_layout_element_size(BtLayoutElement * e, bool b_x_axis)
{
    return b_x_axis ? &e->w : &e->h;
}

BT_LOCAL float * bt__get_layout_element_min_size(BtLayoutElement * e, bool b_x_axis)
{
    return b_x_axis ? &e->min_w : &e->min_h;
}

BT_LOCAL BtAxisSizing * bt__get_layout_element_sizing(BtLayoutElement * e, bool b_x_axis)
{
    return b_x_axis ? &e->desc.sizing_w : &e->desc.sizing_h;
}

// ==========================================================
// Layout Phases
// ==========================================================

BT_LOCAL void bt__compute_intrinsic_sizes(BtLayoutBuildContext * ctx, BtLayoutElement * root)
{
    if(!root)
        return;

    // Depth-first post-order traversal: visit all descendants of a node before visiting it
    // -> build a reversed post-order stack, then pop from it
    bt__stack_clear(&ctx->phases.intrinsic_sizes.dfs_stack_0);
    bt__stack_clear(&ctx->phases.intrinsic_sizes.dfs_stack_1);
    bt__stack_push(&ctx->phases.intrinsic_sizes.dfs_stack_0, root);
    while(!bt__stack_is_empty(&ctx->phases.intrinsic_sizes.dfs_stack_0))
    {
        BtLayoutElement * layout_element = bt__stack_pop(&ctx->phases.intrinsic_sizes.dfs_stack_0);
        bt__stack_push(&ctx->phases.intrinsic_sizes.dfs_stack_1, layout_element);

        for(BtLayoutElement * child = layout_element->links.first_child; child != NULL; child = child->links.next_sibling)
        {
            bt__stack_push(&ctx->phases.intrinsic_sizes.dfs_stack_0, child);
        }
    }

    while(!bt__stack_is_empty(&ctx->phases.intrinsic_sizes.dfs_stack_1))
    {
        BtLayoutElement * layout_element = bt__stack_pop(&ctx->phases.intrinsic_sizes.dfs_stack_1);

        const float padding_x = (float)(layout_element->desc.padding.l + layout_element->desc.padding.r);
        const float padding_y = (float)(layout_element->desc.padding.t + layout_element->desc.padding.b);

        layout_element->w     = padding_x;
        layout_element->min_w = padding_x;
        layout_element->h     = padding_y;
        layout_element->min_h = padding_y;

        if(layout_element->desc.layout_dir == BT_LAYOUT_DIR_LEFT_TO_RIGHT)
        {
            if(layout_element->links.first_child)
            {
                int num_children = 0;
                for(BtLayoutElement * child = layout_element->links.first_child; child != NULL; child = child->links.next_sibling)
                {
                    layout_element->w     += child->w;
                    layout_element->min_w += child->min_w;

                    layout_element->h     = fmaxf(layout_element->h, child->h + padding_y);
                    layout_element->min_h = fmaxf(layout_element->min_h, child->min_h + padding_y);

                    num_children += 1;
                }

                const float child_gap  = (float)((num_children - 1) * layout_element->desc.child_gap);
                layout_element->w     += child_gap;
                layout_element->min_w += child_gap;
            }
        }
        else if(layout_element->desc.layout_dir == BT_LAYOUT_DIR_TOP_TO_BOTTOM)
        {
            if(layout_element->links.first_child)
            {
                int num_children = 0;
                for(BtLayoutElement * child = layout_element->links.first_child; child != NULL; child = child->links.next_sibling)
                {
                    layout_element->h     += child->h;
                    layout_element->min_h += child->min_h;

                    layout_element->w     = fmaxf(layout_element->w, child->w + padding_x);
                    layout_element->min_w = fmaxf(layout_element->min_w, child->min_w + padding_x);

                    num_children += 1;
                }

                const float child_gap  = (float)((num_children - 1) * layout_element->desc.child_gap);
                layout_element->h     += child_gap;
                layout_element->min_h += child_gap;
            }
        }

        // If the user didn't specify a maximum size, set it to FLT_MAX
        if(layout_element->desc.sizing_w.min_max.max <= 0)
            layout_element->desc.sizing_w.min_max.max = FLT_MAX;
        if(layout_element->desc.sizing_h.min_max.max <= 0)
            layout_element->desc.sizing_h.min_max.max = FLT_MAX;

        if(layout_element->desc.sizing_w.basis == BT_BASIS_PERCENT)
        {
            layout_element->w = 0; // Will be computed during container sizing (see bt__size_containers_along_axis)
        }
        else
        {
            if(layout_element->desc.sizing_w.basis == BT_BASIS_FIXED)
            {
                layout_element->w = layout_element->desc.sizing_w.value.fixed;
                if(layout_element->desc.sizing_w.shrink == 0)
                    layout_element->min_w = layout_element->desc.sizing_w.value.fixed; // Cannot shrink below preferred size
                // else: min_w stays at content-based minimum (can shrink in overflow)
            }
            // else BT_BASIS_AUTO: w and min_w already accumulated from children above

            // Clamp element width according to the sizing configuration values
            layout_element->w     = bt__clamp(layout_element->w, layout_element->desc.sizing_w.min_max.min, layout_element->desc.sizing_w.min_max.max);
            layout_element->min_w = bt__clamp(layout_element->min_w, layout_element->desc.sizing_w.min_max.min, layout_element->desc.sizing_w.min_max.max);
        }

        if(layout_element->desc.sizing_h.basis == BT_BASIS_PERCENT)
        {
            layout_element->h = 0; // Will be computed during container sizing (see bt__size_containers_along_axis)
        }
        else
        {
            if(layout_element->desc.sizing_h.basis == BT_BASIS_FIXED)
            {
                layout_element->h = layout_element->desc.sizing_h.value.fixed;
                if(layout_element->desc.sizing_h.shrink == 0)
                    layout_element->min_h = layout_element->desc.sizing_h.value.fixed; // Cannot shrink below preferred size
                // else: min_h stays at content-based minimum (can shrink in overflow)
            }
            // else BT_BASIS_AUTO: h and min_h already accumulated from children above

            // Clamp element height according to the sizing configuration values
            layout_element->h     = bt__clamp(layout_element->h, layout_element->desc.sizing_h.min_max.min, layout_element->desc.sizing_h.min_max.max);
            layout_element->min_h = bt__clamp(layout_element->min_h, layout_element->desc.sizing_h.min_max.min, layout_element->desc.sizing_h.min_max.max);
        }
    }
}

BT_LOCAL void bt__size_containers_along_axis(BtLayoutBuildContext * ctx, const BtLayoutConfig * config, BtLayoutElement * root, bool b_x_axis)
{
    if(root->desc.sizing_w.basis != BT_BASIS_PERCENT)
        root->w = bt__clamp(root->w, root->desc.sizing_w.min_max.min, root->desc.sizing_w.min_max.max);
    if(root->desc.sizing_h.basis != BT_BASIS_PERCENT)
        root->h = bt__clamp(root->h, root->desc.sizing_h.min_max.min, root->desc.sizing_h.min_max.max);

    bt__array_clear(&ctx->phases.size_axis.bfs_buffer);
    bt__array_add(&ctx->phases.size_axis.bfs_buffer, root);

    for(int i = 0; i < ctx->phases.size_axis.bfs_buffer.count; ++i)
    {
        BtLayoutElement * parent = ctx->phases.size_axis.bfs_buffer.data[i];

        int num_grow_containers   = 0;
        int num_shrink_containers = 0;

        const float parent_size = b_x_axis ? parent->w : parent->h;

        const float parent_padding =
            b_x_axis ? (float)(parent->desc.padding.l + parent->desc.padding.r) : (float)(parent->desc.padding.t + parent->desc.padding.b);

        float inner_content_size           = 0;
        float total_padding_and_child_gaps = parent_padding;

        const bool b_sizing_along_axis =
            (b_x_axis && parent->desc.layout_dir == BT_LAYOUT_DIR_LEFT_TO_RIGHT) || (!b_x_axis && parent->desc.layout_dir == BT_LAYOUT_DIR_TOP_TO_BOTTOM);

        const float child_gap = parent->desc.child_gap;
        const float snap      = bt__get_snap(config);

        bt__array_clear(&ctx->phases.size_axis.resizable_containers);

        int num_percent_children = 0;
        for(BtLayoutElement * child = parent->links.first_child; child != NULL; child = child->links.next_sibling)
        {
            const BtAxisSizing child_sizing = *bt__get_layout_element_sizing(child, b_x_axis);
            const float        child_size   = *bt__get_layout_element_size(child, b_x_axis);

            if(child->links.first_child != NULL)
                bt__array_add(&ctx->phases.size_axis.bfs_buffer, child);

            const bool b_is_fixed   = (child_sizing.basis == BT_BASIS_FIXED);
            const bool b_is_percent = (child_sizing.basis == BT_BASIS_PERCENT);

            if(!b_is_percent && (child_sizing.shrink > 0 || (!b_is_fixed && child_sizing.grow > 0)))
                bt__array_add(&ctx->phases.size_axis.resizable_containers, child);

            if(b_is_percent)
                num_percent_children += 1;

            if(b_sizing_along_axis) // Along layout axis: take sum of children size + gaps
            {
                inner_content_size += b_is_percent ? 0 : child_size;

                if(child_sizing.grow > 0)
                    num_grow_containers += 1;
                if(child_sizing.shrink > 0)
                    num_shrink_containers += 1;

                if(child != parent->links.first_child)
                {
                    inner_content_size           += child_gap;
                    total_padding_and_child_gaps += child_gap;
                }
            }
            else // Across layout axis: take max of children size
            {
                inner_content_size = fmaxf(child_size, inner_content_size);
            }
        }

        // Setup size of containers with the "percent" sizing policy
        if(num_percent_children > 0)
        {
            const float parent_size_wo_padding_and_gaps = parent_size - total_padding_and_child_gaps;

            for(BtLayoutElement * child = parent->links.first_child; child != NULL; child = child->links.next_sibling)
            {
                const BtAxisSizing child_sizing = *bt__get_layout_element_sizing(child, b_x_axis);
                if(child_sizing.basis == BT_BASIS_PERCENT)
                {
                    float * child_size = bt__get_layout_element_size(child, b_x_axis);
                    *child_size        = parent_size_wo_padding_and_gaps * child_sizing.value.percent;
                    *child_size        = floorf(*child_size / snap) * snap;
                    *child_size        = bt__clamp(*child_size, child_sizing.min_max.min, child_sizing.min_max.max);
                    if(b_sizing_along_axis)
                        inner_content_size += *child_size;
                }
            }
        }

        // Sizing along layout axis: handle under/overflow
        if(b_sizing_along_axis)
        {
            float total_size_to_distribute = parent_size - parent_padding - inner_content_size;

            bool b_distributed = false;

            // Overflow: shrink resizable children proportionally by shrink weight
            if(total_size_to_distribute < -BT_EPSILON && num_shrink_containers > 0)
            {
                b_distributed = true;

                // Keep only shrinkable containers
                for(int child_idx = 0; child_idx < ctx->phases.size_axis.resizable_containers.count; ++child_idx)
                {
                    const BtAxisSizing * s = bt__get_layout_element_sizing(ctx->phases.size_axis.resizable_containers.data[child_idx], b_x_axis);
                    if(s->shrink == 0)
                    {
                        bt__array_remove_swap_back(&ctx->phases.size_axis.resizable_containers, child_idx);
                        child_idx -= 1;
                    }
                }

                while(total_size_to_distribute < -BT_EPSILON && ctx->phases.size_axis.resizable_containers.count > 0)
                {
                    float total_flex_shrink = 0;
                    for(int child_idx = 0; child_idx < ctx->phases.size_axis.resizable_containers.count; ++child_idx)
                    {
                        BtLayoutElement *  child         = ctx->phases.size_axis.resizable_containers.data[child_idx];
                        const BtAxisSizing child_sizing  = *bt__get_layout_element_sizing(child, b_x_axis);
                        total_flex_shrink               += child_sizing.shrink;
                    }

                    float distributed = 0;
                    for(int child_idx = 0; child_idx < ctx->phases.size_axis.resizable_containers.count; ++child_idx)
                    {
                        BtLayoutElement *  child        = ctx->phases.size_axis.resizable_containers.data[child_idx];
                        float *            child_size   = bt__get_layout_element_size(child, b_x_axis);
                        const BtAxisSizing child_sizing = *bt__get_layout_element_sizing(child, b_x_axis);
                        const float        child_min    = *bt__get_layout_element_min_size(child, b_x_axis);
                        const float        prev_size    = *child_size;

                        *child_size += (child_sizing.shrink / total_flex_shrink) * total_size_to_distribute;

                        if(*child_size <= child_min)
                        {
                            *child_size = child_min;
                            bt__array_remove_swap_back(&ctx->phases.size_axis.resizable_containers, child_idx);
                            child_idx -= 1;
                        }
                        distributed += *child_size - prev_size;
                    }
                    total_size_to_distribute -= distributed;
                }
            }
            // Underflow: grow growable children proportionally by grow weight
            else if(total_size_to_distribute > BT_EPSILON && num_grow_containers > 0)
            {
                b_distributed = true;

                // Keep only growable containers
                for(int child_idx = 0; child_idx < ctx->phases.size_axis.resizable_containers.count; ++child_idx)
                {
                    const BtAxisSizing * s = bt__get_layout_element_sizing(ctx->phases.size_axis.resizable_containers.data[child_idx], b_x_axis);
                    if(s->basis == BT_BASIS_FIXED || s->grow == 0)
                    {
                        bt__array_remove_swap_back(&ctx->phases.size_axis.resizable_containers, child_idx);
                        child_idx -= 1;
                    }
                }

                while(total_size_to_distribute > BT_EPSILON && ctx->phases.size_axis.resizable_containers.count > 0)
                {
                    float total_flex_grow = 0;
                    for(int child_idx = 0; child_idx < ctx->phases.size_axis.resizable_containers.count; ++child_idx)
                    {
                        BtLayoutElement *  child         = ctx->phases.size_axis.resizable_containers.data[child_idx];
                        const BtAxisSizing child_sizing  = *bt__get_layout_element_sizing(child, b_x_axis);
                        total_flex_grow                 += child_sizing.grow;
                    }

                    float distributed = 0;
                    for(int child_idx = 0; child_idx < ctx->phases.size_axis.resizable_containers.count; ++child_idx)
                    {
                        BtLayoutElement *  child        = ctx->phases.size_axis.resizable_containers.data[child_idx];
                        float *            child_size   = bt__get_layout_element_size(child, b_x_axis);
                        const BtAxisSizing child_sizing = *bt__get_layout_element_sizing(child, b_x_axis);
                        const float        prev_size    = *child_size;

                        *child_size += (child_sizing.grow / total_flex_grow) * total_size_to_distribute;

                        if(*child_size >= child_sizing.min_max.max)
                        {
                            *child_size = child_sizing.min_max.max;
                            bt__array_remove_swap_back(&ctx->phases.size_axis.resizable_containers, child_idx);
                            child_idx -= 1;
                        }
                        distributed += *child_size - prev_size;
                    }
                    total_size_to_distribute -= distributed;
                }
            }

            // Snap each distributed child to the nearest snapping-grid unit, then redistribute
            // the accumulated fractional remainder 1 snapping-grid unit at a time to preserve total size
            if(b_distributed && ctx->phases.size_axis.resizable_containers.count > 0)
            {
                float remainder = 0.f;
                for(int child_idx = 0; child_idx < ctx->phases.size_axis.resizable_containers.count; ++child_idx)
                {
                    float *     child_size  = bt__get_layout_element_size(ctx->phases.size_axis.resizable_containers.data[child_idx], b_x_axis);
                    const float floored     = floorf(*child_size / snap) * snap;
                    remainder              += *child_size - floored;
                    *child_size             = floored;
                }

                int extra = (int)roundf(remainder / snap);
                for(int child_idx = ctx->phases.size_axis.resizable_containers.count - 1; child_idx >= 0 && extra > 0; --child_idx, --extra)
                {
                    *bt__get_layout_element_size(ctx->phases.size_axis.resizable_containers.data[child_idx], b_x_axis) += snap;
                }
            }
        }
        // Sizing across layout axis
        else
        {
            for(int child_idx = 0; child_idx < ctx->phases.size_axis.resizable_containers.count; ++child_idx)
            {
                BtLayoutElement * child = ctx->phases.size_axis.resizable_containers.data[child_idx];

                float * child_size = bt__get_layout_element_size(child, b_x_axis);

                const BtAxisSizing * child_sizing = bt__get_layout_element_sizing(child, b_x_axis);

                const float child_min_size = *bt__get_layout_element_min_size(child, b_x_axis);

                const float child_max_size = parent_size - parent_padding;

                if(child_sizing->basis != BT_BASIS_FIXED && child_sizing->grow > 0) // Make child fill space if it is growable
                    *child_size = fminf(child_max_size, child_sizing->min_max.max);

                *child_size = bt__clamp(*child_size, child_min_size, child_max_size);
            }
        }
    }
}

BT_LOCAL void bt__position_children(BtLayoutBuildContext * ctx, BtLayoutElement * root)
{
    BtLayoutElementBuffer * stack = &ctx->phases.position_children.stack;
    bt__stack_clear(stack);
    bt__stack_push(stack, root);

    while(!bt__stack_is_empty(stack))
    {
        BtLayoutElement * parent = bt__stack_pop(stack);

        float offset = parent->desc.layout_dir == BT_LAYOUT_DIR_LEFT_TO_RIGHT ? parent->x + parent->desc.padding.l : parent->y + parent->desc.padding.t;

        for(BtLayoutElement * child = parent->links.first_child; child != NULL; child = child->links.next_sibling)
        {
            if(parent->desc.layout_dir == BT_LAYOUT_DIR_LEFT_TO_RIGHT)
            {
                child->x  = offset;
                child->y  = parent->y + parent->desc.padding.t;
                offset   += child->w + parent->desc.child_gap;
            }
            else
            {
                child->x  = parent->x + parent->desc.padding.l;
                child->y  = offset;
                offset   += child->h + parent->desc.child_gap;
            }

            if(child->links.first_child != NULL)
                bt__stack_push(stack, child);
        }
    }
}

BT_API void bt_compute_layout(
    const BtLayoutConfig * config,
    BtLayoutBuildContext * ctx,
    BtLayoutElement *      root,
    float                  root_x,
    float                  root_y,
    float                  root_w,
    float                  root_h
)
{
    if(!root || !root->links.first_child)
        return;

    // The root element is special: position and size are set by user
    root->x             = root_x;
    root->y             = root_y;
    root->w             = root_w;
    root->h             = root_h;
    root->desc.sizing_w = BT_LITERAL(BtAxisSizing, .basis = BT_BASIS_FIXED, .value = { .fixed = root_w });
    root->desc.sizing_h = BT_LITERAL(BtAxisSizing, .basis = BT_BASIS_FIXED, .value = { .fixed = root_h });

    bt__compute_intrinsic_sizes(ctx, root);
    bt__size_containers_along_axis(ctx, config, root, true);
    bt__size_containers_along_axis(ctx, config, root, false);
    bt__position_children(ctx, root);
}

// ================================================================================================
// Splitter resizing
// ================================================================================================

// Queued splitter resize operation
typedef struct BtPendingResize
{
    BtLayoutElement * splitter;
    float             delta;
    uint32_t          b_x_axis : 1;
    uint32_t          pad0_    : 31;
} BtPendingResize;

BT_LOCAL BtLayoutElement * bt__hit_test_splitter(BtLayoutElement * node, float x, float y)
{
    if(node->type == BT_LAYOUT_ELEMENT_TYPE_SPLITTER)
    {
        const bool  b_x_axis = node->links.parent->desc.layout_dir == BT_LAYOUT_DIR_LEFT_TO_RIGHT;
        const float pad      = node->desc.splitter_hit_area_padding;
        const float hx       = node->x - (b_x_axis ? pad : 0.f);
        const float hy       = node->y - (b_x_axis ? 0.f : pad);
        const float hw       = node->w + (b_x_axis ? 2.f * pad : 0.f);
        const float hh       = node->h + (b_x_axis ? 0.f : 2.f * pad);
        if(x >= hx && x < hx + hw && y >= hy && y < hy + hh)
            return node;
    }
    for(BtLayoutElement * c = node->links.first_child; c; c = c->links.next_sibling)
    {
        BtLayoutElement * hit = bt__hit_test_splitter(c, x, y);
        if(hit)
            return hit;
    }
    return NULL;
}

BT_LOCAL bool bt__process_splitter_mouse_inputs(
    BtSplitterState *     splitter_state,
    BtPendingResize *     pending_resize,
    BtLayoutElement *     root,
    const BtMouseInputs * mouse
)
{
    BtLayoutElement * splitter = bt__hit_test_splitter(root, mouse->pos_x, mouse->pos_y);

    if(mouse->pressed)
    {
        splitter_state->active_splitter = splitter;
        splitter_state->dragged         = true;
    }

    if(mouse->released)
    {
        splitter_state->active_splitter = NULL;
        splitter_state->dragged         = false;
    }

    if(!mouse->held && splitter)
    {
        splitter_state->active_splitter = splitter;
        splitter_state->hovered         = true;
    }
    else
    {
        splitter_state->hovered = false;
    }

    if(mouse->held && splitter_state->active_splitter && splitter_state->dragged)
    {
        const bool  b_x_axis = splitter_state->active_splitter->links.parent->desc.layout_dir == BT_LAYOUT_DIR_LEFT_TO_RIGHT;
        const float delta    = b_x_axis ? mouse->delta_x : mouse->delta_y;
        if(fabsf(delta) > BT_EPSILON)
        {
            pending_resize->splitter = splitter_state->active_splitter;
            pending_resize->delta    = delta;
            pending_resize->b_x_axis = b_x_axis;
            return true;
        }
    }
    else if(splitter_state->active_splitter && !splitter)
    {
        splitter_state->active_splitter = NULL;
    }

    return false;
}

// Adjusts the sizing of e by delta along b_x_axis.
// Grow and Percent elements are converted to BT_BASIS_FIXED with grow = 0 so they hold their
// new size across frames; shrink is preserved to allow overflow shrinking.
// Fixed elements update their fixed size directly.
// Auto elements with grow == 0 are unaffected.
// Changes take effect on the next layout pass.
BT_LOCAL void bt__apply_resize_to_element(const BtLayoutConfig * config, BtLayoutElement * e, float delta, bool b_x_axis)
{
    BtAxisSizing * s        = bt__get_layout_element_sizing(e, b_x_axis);
    float *        size     = bt__get_layout_element_size(e, b_x_axis);
    const float    new_size = bt__clamp(bt__snap_to_grid(config, *size + delta), s->min_max.min, s->min_max.max);
    if(s->grow > 0 || s->basis == BT_BASIS_PERCENT)
    {
        s->grow  = 0;
        s->basis = BT_BASIS_FIXED;
        // shrink stays as-is
    }
    if(s->basis == BT_BASIS_FIXED)
        s->value.fixed = new_size;
}

// Computes the actual clamped delta the splitter can move along b_x_axis.
// prev_sibling grows/shrinks by at most delta; next_sibling absorbs the remainder.
// Returns 0 if the splitter cannot move (missing neighbours or all limits hit).
//
// When next is the last child, empty space between it and the parent edge acts as a buffer:
//   delta > 0 (prev grows):   empty space is consumed first before next shrinks.
//   delta < 0 (prev shrinks): next grows up to its max; excess leaves a gap before the parent edge.
BT_LOCAL float bt__compute_splitter_actual_delta(const BtLayoutConfig * config, const BtLayoutElement * splitter, float delta, bool b_x_axis)
{
    BtLayoutElement * prev = splitter->links.prev_sibling;
    BtLayoutElement * next = splitter->links.next_sibling;
    if(!prev || !next)
        return 0.f;

    // Clamp delta by what prev can take
    BtAxisSizing * sp            = bt__get_layout_element_sizing(prev, b_x_axis);
    const float    prev_size     = *bt__get_layout_element_size(prev, b_x_axis);
    const float    prev_min_size = fmaxf(sp->min_max.min, *bt__get_layout_element_min_size(prev, b_x_axis));
    const float    new_prev_size = bt__clamp(bt__snap_to_grid(config, prev_size + delta), prev_min_size, sp->min_max.max);
    float          actual_delta  = new_prev_size - prev_size;
    if(fabsf(actual_delta) < BT_EPSILON)
        return 0.f;

    BtAxisSizing * sn            = bt__get_layout_element_sizing(next, b_x_axis);
    const float    next_size     = *bt__get_layout_element_size(next, b_x_axis);
    const float    next_min_size = fmaxf(sn->min_max.min, *bt__get_layout_element_min_size(next, b_x_axis));

    // When next is the last child, compute empty space between it and the parent edge.
    // Fixed, Percent, and inert Auto (grow == 0) last children are never resized; the gap shifts.
    // Grow Auto (grow > 0) last children are also never resized explicitly; they fill naturally each frame.
    const bool b_next_is_last   = (next->links.next_sibling == NULL);
    const bool b_translate_next = b_next_is_last && !(sn->basis == BT_BASIS_AUTO && sn->grow > 0);

    float empty_space = 0.f;
    if(b_next_is_last)
    {
        const float next_start   = b_x_axis ? next->x : next->y;
        const float next_end     = next_start + next_size;
        const float parent_start = b_x_axis ? splitter->links.parent->x : splitter->links.parent->y;
        const float parent_sz    = *bt__get_layout_element_size(splitter->links.parent, b_x_axis);
        const float parent_end   = parent_start + parent_sz;
        const float pad_end      = (float)(b_x_axis ? splitter->links.parent->desc.padding.r : splitter->links.parent->desc.padding.b);
        empty_space              = fmaxf(0.f, parent_end - pad_end - next_end);
    }

    if(actual_delta > 0)
    {
        // prev grows: empty_space consumed first; only non-translate elements contribute shrink capacity
        const float shrink_capacity = b_translate_next ? 0.f : (next_size - next_min_size);
        actual_delta                = fminf(actual_delta, empty_space + shrink_capacity);
    }
    else
    {
        // prev shrinks: only non-translate elements contribute grow capacity; gap allowed for last child
        const float grow_capacity = b_translate_next ? 0.f : (sn->min_max.max - next_size);
        if(!b_next_is_last)
            actual_delta = fmaxf(actual_delta, -grow_capacity); // non-last: no gap allowed
    }

    return fabsf(actual_delta) < BT_EPSILON ? 0.f : actual_delta;
}

BT_API bool bt_can_splitter_resize(const BtLayoutConfig * config, const BtLayoutElement * splitter, float delta)
{
    if(splitter->links.parent)
    {
        const bool b_x_axis = (splitter->links.parent->desc.layout_dir == BT_LAYOUT_DIR_LEFT_TO_RIGHT);
        return fabsf(bt__compute_splitter_actual_delta(config, splitter, delta, b_x_axis)) >= BT_EPSILON;
    }
    return false;
}

BT_LOCAL void bt__resize_splitter_neighbour_elements(const BtLayoutConfig * config, BtLayoutElement * splitter, float delta, bool b_x_axis)
{
    float actual_delta = bt__compute_splitter_actual_delta(config, splitter, delta, b_x_axis);
    if(fabsf(actual_delta) < BT_EPSILON)
        return;

    BtLayoutElement * prev = splitter->links.prev_sibling;
    BtLayoutElement * next = splitter->links.next_sibling;

    // Last children are never explicitly resized; the layout engine handles them naturally.
    // Only non-last children need an explicit apply_next_delta to stay in sync.
    const bool  b_next_is_last   = (next->links.next_sibling == NULL);
    const float apply_next_delta = b_next_is_last ? 0.f : -actual_delta;

    // Lock siblings before prev to their current size so they do not spring back on the next layout pass.
    // Converts Auto grow elements to BT_BASIS_FIXED, and snapshots the current rendered size into
    // value.fixed for all Fixed elements to prevent spring-back to a stale preferred size.
    for(BtLayoutElement * s = splitter->links.parent->links.first_child; s != prev; s = s->links.next_sibling)
    {
        if(s->type == BT_LAYOUT_ELEMENT_TYPE_SPLITTER)
            continue;

        BtAxisSizing * ss = bt__get_layout_element_sizing(s, b_x_axis);
        if(ss->grow > 0 && ss->basis != BT_BASIS_PERCENT)
        {
            ss->grow  = 0;
            ss->basis = BT_BASIS_FIXED;
            // shrink stays as-is
        }

        if(ss->basis == BT_BASIS_FIXED)
            ss->value.fixed = *bt__get_layout_element_size(s, b_x_axis);
    }

    bt__apply_resize_to_element(config, prev, actual_delta, b_x_axis);

    if(fabsf(apply_next_delta) > BT_EPSILON)
        bt__apply_resize_to_element(config, next, apply_next_delta, b_x_axis);
}

BT_API bool bt_process_splitter_interactions(
    const BtLayoutConfig * config,
    BtLayoutBuildContext * ctx,
    BtSplitterState *      splitter_state,
    BtLayoutElement *      root,
    const BtMouseInputs *  mouse_inputs
)
{
    BtPendingResize pending_resize = { 0 };
    if(bt__process_splitter_mouse_inputs(splitter_state, &pending_resize, root, mouse_inputs))
    {
        bt__resize_splitter_neighbour_elements(config, pending_resize.splitter, pending_resize.delta, (bool)pending_resize.b_x_axis);
        bt_compute_layout(config, ctx, root, root->x, root->y, root->w, root->h);
        return true;
    }
    return false;
}

BT_API void bt_clear_layout_element_links(BtLayoutElement * layout_element)
{
    layout_element->links.parent       = NULL;
    layout_element->links.first_child  = NULL;
    layout_element->links.prev_sibling = NULL;
    layout_element->links.next_sibling = NULL;
}

#endif // BT_IMPLEMENTATION

#endif // BENTO_H
