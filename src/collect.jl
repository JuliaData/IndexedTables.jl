to_length(n::Integer) = n
to_length(t::Tuple{Vararg{Integer}}) = prod(t)
to_length(t::Tuple{Vararg{AbstractUnitRange}}) = prod(map(length, t))

default_initializer(::Type{T}, sz) where {T} = similar(arrayof(T), to_length(sz))

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

_append!!(v, itr) = append!!(v, itr)
_append!!(v::StructArray{NamedTuple{(),Tuple{}}}, itr) = collect_columns(itr)

collect_columns_flattened(itr) = foldl(_append!!, itr, init = Columns())
