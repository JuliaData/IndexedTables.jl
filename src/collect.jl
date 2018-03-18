collectcolumns(itr) = collectcolumns(itr, Base.iteratorsize(itr))

function collectcolumns(itr, ::Union{Base.HasShape, Base.HasLength})
    st = start(itr)
    el, st = next(itr, st)
    dest = similar(arrayof(typeof(el)), length(itr))
    dest[1] = el
    collect_to_columns!(dest, itr, 2, st)
end

function collect_to_columns!(dest::Columns{T, U}, itr, offs, st) where {T, U}
    # collect to dest array, checking the type of each result. if a result does not
    # match, widen the result type and re-dispatch.
    i = offs
    while !done(itr, st)
        el, st = next(itr, st)
        if fieldwise_isa(el, T)
            @inbounds dest[i] = el::T
            i += 1
        else
            S = typeof(el)
            sp, tp = S.parameters, T.parameters
            idx = find(!(s <: t) for (s, t) in zip(sp, tp))
            new = dest
            for l in idx
                newcol = Array{typejoin(sp[l], tp[l])}(length(dest))
                copy!(newcol, 1, column(dest, l), 1, i-1)
                new = setcol(new, l, newcol)
            end
            @inbounds new[i] = el
            return collect_to_columns!(new, itr, i+1, st)
        end
    end
    return dest
end

@generated function fieldwise_isa(el::S, ::Type{T}) where {S, T}
    if all((s <: t) for (s, t) in zip(S.parameters, T.parameters))
        return :(true)
    else
        return :(false)
    end
end
