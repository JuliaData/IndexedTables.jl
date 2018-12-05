_is_subtype(::Type{S}, ::Type{T}) where {S, T} = promote_type(S, T) == T

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
collect_columns(itr) = collect_columns(itr, Base.IteratorSize(itr))

function collect_empty_columns(itr::T) where {T}
    S = Core.Compiler.return_type(first, Tuple{T})
    similar(arrayof(S), 0)
end

function collect_columns(@nospecialize(itr), ::Union{Base.HasShape, Base.HasLength})
    st = iterate(itr)
    st === nothing && return collect_empty_columns(itr)
    el, i = st
    dest = similar(arrayof(typeof(el)), length(itr))
    dest[1] = el
    collect_to_columns!(dest, itr, 2, i)
end

function collect_to_columns!(dest::AbstractArray{T}, itr, offs, st) where {T}
    # collect to dest array, checking the type of each result. if a result does not
    # match, widen the result type and re-dispatch.
    i = offs
    while true
        elem = iterate(itr, st)
        elem === nothing && break
        el, st = elem
        if fieldwise_isa(el, T)
            @inbounds dest[i] = el
            i += 1
        else
            new = widencolumns(dest, i, el, T)
            @inbounds new[i] = el
            return collect_to_columns!(new, itr, i+1, st)
        end
    end
    return dest
end

function collect_columns(itr, ::Base.SizeUnknown)
    elem = iterate(itr)
    elem === nothing && return collect_empty_columns(itr)
    el, st = elem
    dest = similar(arrayof(typeof(el)), 1)
    dest[1] = el
    grow_to_columns!(dest, itr, iterate(itr, st))
end

function collect_columns_flattened(itr)
    elem = iterate(itr)
    @assert elem !== nothing
    el, st = elem
    collect_columns_flattened(itr, el, st)
end

function collect_columns_flattened(itr, el, st)
    while isempty(el)
        elem = iterate(itr, st)
        elem === nothing && return collect_empty_columns(el)
        el, st = elem
    end
    dest = collect_columns(el)
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
    while isempty(el.second)
        elem = iterate(itr, st)
        elem === nothing && return collect_empty_columns(el.first => i for i in el.second)
        el, st = elem
    end
    dest_data = collect_columns(el.second)
    dest_key = collect_columns(el.first for i in dest_data)
    collect_columns_flattened!(Columns(dest_key => dest_data), itr, el, st)
end

function collect_columns_flattened!(dest::Columns{<:Pair}, itr, el::Pair, st)
    dest_key, dest_data = dest.columns
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

function grow_to_columns!(dest::AbstractArray{T}, itr, elem = iterate(itr)) where {T}
    # collect to dest array, checking the type of each result. if a result does not
    # match, widen the result type and re-dispatch.
    i = length(dest)+1
    while elem !== nothing
        el, st = elem
        if fieldwise_isa(el, T)
            push!(dest, el)
            elem = iterate(itr, st)
            i += 1
        else
            new = widencolumns(dest, i, el, T)
            push!(new, el)
            return grow_to_columns!(new, itr, iterate(itr, st))
        end
    end
    return dest
end

# extra methods if we have widened to Vector{Tuple} or Vector{NamedTuple}
# better to not generate as this is the case where the user is sending heterogenoeus data
fieldwise_isa(el::S, ::Type{Tuple}) where {S<:Tup} = _is_subtype(S, Tuple)
fieldwise_isa(el::S, ::Type{NamedTuple}) where {S<:Tup} = _is_subtype(S, NamedTuple)

@generated function fieldwise_isa(el::S, ::Type{T}) where {S<:Tup, T<:Tup}
    if (fieldnames(S) == fieldnames(T)) && all(_is_subtype(s, t) for (s, t) in zip(fieldtypes(S), fieldtypes(T)))
        return :(true)
    else
        return :(false)
    end
end

@generated function fieldwise_isa(el::S, ::Type{T}) where {S, T}
    if _is_subtype(S, T)
        return :(true)
    else
        return :(false)
    end
end

fieldwise_isa(el::Pair, ::Type{Pair{T1, T2}}) where {T1, T2}  =
    fieldwise_isa(el.first, T1) && fieldwise_isa(el.second, T2)

function widencolumns(dest, i, el::S, ::Type{T}) where{S <: Tup, T<:Tup}
    if fieldnames(S) != fieldnames(T) || T == Tuple || T == NamedTuple
        R = (S <: Tuple) && (T <: Tuple) ? Tuple :  (S <: NamedTuple) && (T <: NamedTuple) ? NamedTuple : Any
        new = Array{R}(undef, length(dest))
        copyto!(new, 1, dest, 1, i-1)
    else
        sp, tp = fieldtypes(S), fieldtypes(T)
        idx = findall(collect(!(s <: t) for (s, t) in zip(sp, tp)))
        new = dest
        for l in idx
            newcol = Vector{promote_type(sp[l], tp[l])}(undef, length(dest))
            copyto!(newcol, 1, column(dest, l), 1, i-1)
            new = setcol(new, l, newcol)
        end
    end
    new
end

function widencolumns(dest, i, el::S, ::Type{T}) where{S, T}
    new = Vector{promote_type(S, T)}(undef, length(dest))
    copyto!(new, 1, dest, 1, i-1)
    new
end

function widencolumns(dest::Columns{<:Pair}, i, el::Pair, ::Type{Pair{T1, T2}}) where{T1, T2}
    dest1 = fieldwise_isa(el.first, T1) ? dest.columns.first : widencolumns(dest.columns.first, i, el.first, T1)
    dest2 = fieldwise_isa(el.second, T2) ? dest.columns.second : widencolumns(dest.columns.second, i, el.second, T2)
    Columns(dest1 => dest2)
end
