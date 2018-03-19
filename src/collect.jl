"""
`collect_columns(itr)`

Collect an iterable as a `Columns` object if it iterates `Tuples` or `NamedTuples`, as a normal
`Array` otherwise.

## Examples

```jldoctest collect
julia> s = [(1,2), (3,4)];

julia> collect_columns(s)
2-element Columns{Tuple{Int64,Int64}}:
 (1, 2)
 (3, 4)

 julia> s = Iterators.filter(isodd, 1:8);

 julia> collect_columns(s)
 4-element Array{Int64,1}:
  1
  3
  5
  7
```
"""
collect_columns(itr) = collect_columns(itr, Base.iteratorsize(itr))

function collect_columns(itr, ::Union{Base.HasShape, Base.HasLength})
    st = start(itr)
    el, st = next(itr, st)
    dest = similar(arrayof(typeof(el)), length(itr))
    dest[1] = el
    collect_to_columns!(dest, itr, 2, st)
end

function collect_to_columns!(dest::AbstractArray{T}, itr, offs, st) where {T}
    # collect to dest array, checking the type of each result. if a result does not
    # match, widen the result type and re-dispatch.
    i = offs
    while !done(itr, st)
        el, st = next(itr, st)
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
    st = start(itr)
    el, st = next(itr, st)
    dest = similar(arrayof(typeof(el)), 1)
    dest[1] = el
    grow_to_columns!(dest, itr, 2, st)
end

function grow_to_columns!(dest::AbstractArray{T}, itr, offs, st) where {T}
    # collect to dest array, checking the type of each result. if a result does not
    # match, widen the result type and re-dispatch.
    i = offs
    while !done(itr, st)
        el, st = next(itr, st)
        if fieldwise_isa(el, T)
            push!(dest, el)
            i += 1
        else
            new = widencolumns(dest, i, el, T)
            push!(new, el)
            return grow_to_columns!(new, itr, i+1, st)
        end
    end
    return dest
end

@generated function fieldwise_isa(el::S, ::Type{T}) where {S<:Tup, T}
    if all((s <: t) for (s, t) in zip(S.parameters, T.parameters))
        return :(true)
    else
        return :(false)
    end
end

@generated function fieldwise_isa(el::S, ::Type{T}) where {S, T}
    if S <: T
        return :(true)
    else
        return :(false)
    end
end

function widencolumns(dest, i, el::S, ::Type{T}) where{S <: Tup, T}
    sp, tp = S.parameters, T.parameters
    idx = find(!(s <: t) for (s, t) in zip(sp, tp))
    new = dest
    for l in idx
        newcol = Array{promote_type(sp[l], tp[l])}(length(dest))
        copy!(newcol, 1, column(dest, l), 1, i-1)
        new = setcol(new, l, newcol)
    end
    new
end

function widencolumns(dest, i, el::S, ::Type{T}) where{S, T}
    new = Array{promote_type(S, T)}(length(dest))
    copy!(new, 1, dest, 1, i-1)
    new
end
