const default_initializer = ArrayInitializer(t -> t<:Union{Tuple, NamedTuple, Pair}, (T, sz) -> similar(arrayof(T), sz))

"""
    collect_columns(itr)

Collect an iterable as a `Columns` object if it iterates `Tuples` or `NamedTuples`, as a normal
`Array` otherwise.

# Examples

    s = [(1,2), (3,4)]
    collect_columns(s)

    s2 = Iterators.filter(isodd, 1:8)
    collect_columns(s2)
"""
collect_columns(v) = vec(collect_structarray(v, initializer = default_initializer))
collect_columns(s::StructVector) = s

_append!!(v, itr) = append!!(v, itr)
_append!!(v::StructArray{NamedTuple{(),Tuple{}}}, itr) = collect_columns(itr)

collect_columns_flattened(itr) = reduce(_append!!, itr, init = Columns())
