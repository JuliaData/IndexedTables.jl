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
            Rparams = map(typejoin, T.parameters, S.parameters)
            R = get_tuple_type_from_params(el, Rparams)
            new = similar(arrayof(R), length(itr))
            @inbounds for l in 1:i-1; new[l] = dest[l]; end
            @inbounds new[i] = el
            return collect_to_columns!(new, itr, i+1, st)
        end
    end
    return dest
end

get_tuple_type_from_params(el::Tuple, params) = Tuple{params...}
get_tuple_type_from_params(el::NamedTuple, params) = eval(:(NamedTuples.@NT($(keys(el)...)))){params...}

@generated function fieldwise_isa(el::S, ::Type{T}) where {S, T}
    if all((s <: t) for (s, t) in zip(S.parameters, T.parameters))
        return :(true)
    else
        return :(false)
    end
end
