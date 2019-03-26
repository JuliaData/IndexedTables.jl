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
collect_columns(args...) = vec(collect_structarray(args..., initializer = default_initializer))
collect_columns(s::StructVector) = s
collect_empty_columns(itr) = collect_empty_structarray(itr, initializer = default_initializer)

grow_to_columns!(args...) = grow_to_structarray!(args...)
collect_to_columns!(args...) = collect_to_structarray!(args...)

function collect_columns_flattened(itr)
    elem = iterate(itr)
    (elem === nothing) && return Columns()
    el, st = elem
    collect_columns_flattened(itr, el, st)
end

function collect_columns_flattened(itr, el, st)
    fr = iterate(el)
    while fr === nothing
        elem = iterate(itr, st)
        elem === nothing && return collect_empty_columns(el)
        el, st = elem
        fr = iterate(el)
    end
    dest = collect_columns(el, fr)
    collect_columns_flattened!(dest, itr, el, st)
end

function collect_columns_flattened!(dest, itr, el, st)
    while true
        elem = iterate(itr, st)
        elem === nothing && break
        el, st = elem
        dest = grow_to_columns!(dest, el)
    end
    return dest
end

function collect_columns_flattened(itr, el::Pair, st)
    fr = iterate(el.second)
    while fr === nothing
        elem = iterate(itr, st)
        elem === nothing && return collect_empty_columns(el.first => i for i in el.second)
        el, st = elem
        fr = iterate(el.second)
    end
    dest_data = collect_columns(el.second, fr)
    dest_key = collect_columns(el.first for i in dest_data)
    collect_columns_flattened!(Columns(dest_key => dest_data), itr, el, st)
end

function collect_columns_flattened!(dest::Columns{<:Pair}, itr, el::Pair, st)
    dest_key, dest_data = columns(dest)
    while true
        elem = iterate(itr, st)
        elem === nothing && break
        el, st = elem
        n = length(dest_data)
        dest_data = grow_to_columns!(dest_data, el.second)
        dest_key = grow_to_columns!(dest_key, el.first for i in (n+1):length(dest_data))
    end
    return Columns(dest_key => dest_data)
end
