/++
This is a submodule of $(MREF mir, ndslice).

License:   $(HTTP boost.org/LICENSE_1_0.txt, Boost License 1.0).
Copyright: Copyright © 2017-, Ilya Yaroshenko
Authors:   Ilya Yaroshenko

Macros:
SUBREF = $(REF_ALTTEXT $(TT $2), $2, mir, ndslice, $1)$(NBSP)
T2=$(TR $(TDNW $(LREF $1)) $(TD $+))
+/
module mir.ndslice.stack;

import std.traits;
import std.meta;

import mir.ndslice.internal;
import mir.ndslice.slice;
import mir.internal.utility;

@fastmath:

/++
Creates a $(LREF Stack) view of multiple slices.

Can be used in combination with itself, $(LREF until), $(SUBREF, allocation, slice),
and $(SUBREF slice, Slice) assignment.
until pred returns true.

Returns: true if an element was 

Params:
    slices = tuple of slices and stacks. All slices and stacks must have the same dimension count.

Returns: $(LREF Stack).
+/
auto stack(size_t dim = 0, Slices...)(Slices slices)
{
    return Stack!(dim, Slices)(slices);
}

/// 1D
unittest
{
    import mir.ndslice.allocation: slice;
    import mir.ndslice.topology: iota;

    size_t i;
    auto a = 3.iota;
    auto b = iota([6], a.length);
    auto s = stack(a, b);
    assert(s.length == a.length + b.length);
    // iteration with until
    s.until!((elem){ assert(elem == i++); return false; });
    // allocation with slice
    assert(s.slice == s.length.iota);
    // assignment
    auto d = slice!double(s.length);
    d[] = s;
    assert(d == s.length.iota);
    d[] += s;
    assert(d == iota([s.length], 0, 2));
}

/// Multidimensional
unittest
{
    import mir.ndslice.allocation: slice;
    import mir.ndslice.topology: iota;

    // 0, 1, 2
    // 3, 4, 5
    auto a = iota(2, 3);
    // 0, 1
    // 2, 3
    auto b = iota(2, 2);
    // 0, 1, 2, 3, 4
    auto c = iota(1, 5);

    // 0, 1, 2, | 0, 1
    // 3, 4, 5, | 2, 3
    // ---------------
    // 0, 1, 2,   3, 4
    auto s = stack(stack!1(a, b), c);
    // allocation
    auto d = s.slice;
    assert(d == [
        [0, 1, 2, 0, 1],
        [3, 4, 5, 2, 3],
        [0, 1, 2, 3, 4],
        ]);
}

template frontOf(size_t N)
{
    static if (N == 0)
        enum frontOf = "";
    else
    {
        enum i = N - 1;
        enum frontOf = frontOf!i ~ "slices[" ~ i.stringof ~ "].front!d, ";
    }
}

///
enum bool isStack(T) = is(T : Stack!(dim, Slices), size_t dim, Slices...);
///
enum size_t stackDimension(T : Stack!(dim, Slices), size_t dim, Slices...) = dim; 

///
struct Stack(size_t dim, Slices...)
    if (Slices.length > 1)
{
    /// Slices and sub-stacks
    Slices _slices;

    static if (isSlice!(Slices[0]))
    /// Dimension count
        enum N = isSlice!(Slices[0])[0];
    else
        enum N = Slices[0].N;

    static assert(dim < N);

    package alias DeepElemType = CommonType!(staticMap!(DeepElementType, Slices));

    /// Length primitive
    size_t length(size_t d = 0)() const @property
    {
        static if (d == dim)
        {
            size_t length;
            foreach(i; Iota!(Slices.length))
                length += _slices[i].length!d;
            return length;
        }
        else
        {
            return _slices[0].length!d;
        }
    }

    /// Total elements count in the stack.
    size_t elementsCount()() const @property
    {
        size_t count = 1;
        foreach(i; Iota!N)
            count *= length!i;
        return count;
    }

    /// Shape of the stack.
    size_t[N] shape()() const @property
    {
        typeof(return) ret = void;
        foreach(i; Iota!N)
            ret[i] = length!i;
        return ret;
    }

    /// Multidimensional input range primitives
    bool empty(size_t d = 0)() const @property
        if (d != dim)
    {
        return _slices[0].empty!d;
    }

    /// ditto
    void popFront(size_t d = 0)()
        if (d != dim)
    {
        foreach_reverse (i, ref slice; _slices)
            _slices[i].popFront!d;
    }

    /// ditto
    auto front(size_t d = 0)()
        if (d != dim)
    {
        enum elemDim = d < dim ? dim - 1 : dim;
        alias slices = _slices;
        return mixin(`stack!elemDim(` ~ frontOf!(Slices.length) ~ `)`);
    }
}

/++
Iterates elements in $(SUBREF slice, Slice) or $(LREF Stack)
until pred returns true.

Returns: false if pred returned false for all elements and true otherwise.
+/
template until(alias pred)
{
    import mir.functional: naryFun;
    static if (__traits(isSame, naryFun!pred, pred))
    {
        /++
        Specialization for slices
        Params:
            sl = $(SUBREF slice, Slice)
        +/
        bool until(SliceKind kind, size_t[] packs, Iterator)(Slice!(kind, packs, Iterator) sl)
        {
            static if (packs[0] == 1)
            {
                pragma(inline, false);
                alias f = pred;
            }
            else
                alias f = .until!pred;
            if (!sl.empty) do
            {
                if (f(sl.front))
                    return true;
                sl.popFront;
            }
            while(!sl.empty);
            return false;
        }

        /++
        Specialization for stacks
        Params:
            st = $(LREF Stack)
        +/
        bool until(size_t dim, Slices...)(Stack!(dim, Slices) st)
        {
            static if (dim == 0)
            {
               foreach (i, ref slice; st._slices)
                    if (.until!pred(slice))
                        return true;
            }
            else
            {
                if (!st.empty) do
                {
                    if (.until!pred(st.front))
                        return true;
                    st.popFront;
                }
                while(!st.empty);
            }
            return false;
        }
    }
    else
        alias until = .until!(naryFun!pred);
}
