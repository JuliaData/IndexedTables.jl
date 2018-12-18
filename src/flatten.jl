function dedup_names(ns)
    count = Dict{Symbol,Int}()
    for n in ns
        if haskey(count, n)
            count[n] += 1
        else
            count[n] = 1
        end
    end

    repeated = filter(((k,v),) -> v > 1, count)
    for k in keys(repeated)
        repeated[k] = 0
    end
    [haskey(repeated, n) ? Symbol(n, "_", repeated[n]+=1) : n for n in ns]
end

function mapslices(f, x::NDSparse, dims; name = nothing)
    iterdims = setdiff([1:ndims(x);], map(d->fieldindex(columns(x.index),d), dims))
    idx = Any[Colon() for v in columns(x.index)]

    iter = Columns(astuple(columns(x.index))[[iterdims...]])
    if !isempty(dims) || !issorted(iter)
        iter = sort(iter)
    end

    for j in 1:length(iterdims)
        d = iterdims[j]
        idx[d] = iter[1][j]
    end

    if isempty(dims)
        idx[end] = vcat(idx[end])
    end

    y = f(x[idx...]) # Apply on first slice

    if isa(y, NDSparse)
        # this means we need to concatenate outputs into a big NDSparse
        ns = vcat(collect(dimlabels(x)[iterdims]), collect(dimlabels(y)))
        if !all(x->isa(x, Symbol), ns)
            ns = nothing
        else
            ns = dedup_names(ns)
        end
        n = length(y)
        index_first = similar(iter, n)
        for j=1:n
            @inbounds index_first[j] = iter[1]
        end
        index = Columns((columns(index_first)..., astuple(columns(copy(y.index)))...); names=ns)
        data = copy(y.data)
        output = NDSparse(index, data)
        if isempty(dims)
            _mapslices_itable_singleton!(f, output, x, 2)
        else
            _mapslices_itable!(f, output, x, iter, iterdims, 2)
        end
    else
        ns = dimlabels(x)[iterdims]
        if !all(x->isa(x, Symbol), ns)
            ns = nothing
        end
        index = Columns(Tuple(columns(iter[1:1])); names=ns)
        if isa(y, Tup)
            vec = convert(Columns, [y])
        else
            vec = [y]
        end
        if name === nothing
            output = NDSparse(index, vec)
        else
            output = NDSparse(index, Columns(Tuple(columns(vec)), names=[name]))
        end
        if isempty(dims)
            error("calling mapslices with no dimensions and scalar return value -- use map instead")
        else
            _mapslices_scalar!(f, output, x, iter, iterdims, 2, name!==nothing ? x->(x,) : identity)
        end
    end
end

function _mapslices_scalar!(f, output, x, iter, iterdims, start, coerce)
    idx = Any[Colon() for v in columns(x.index)]

    for i = start:length(iter)
        if i != 1 && roweq(iter, i-1, i) # We've already visited this slice
            continue
        end
        for j in 1:length(iterdims)
            d = iterdims[j]
            idx[d] = iter[i][j]
        end
        if length(idx) == length(iterdims)
            idx[end] = vcat(idx[end])
        end
        y = f(x[idx...])
        push!(output.index, iter[i])
        push!(output.data, coerce(y))
    end
    output
end

function _mapslices_itable_singleton!(f, output, x, start)
    I = output.index
    D = output.data

    I1 = Columns(columns(I)[1:ndims(x)])
    I2 = Columns(columns(I)[ndims(x)+1:end])
    i = start
    for i in start:length(x)
        k = x.index[i]
        y = f(NDSparse(x.index[i:i], x.data[i:i]))
        n = length(y)

        foreach((x,y)->append_n!(x,y,n), columns(I1), k)
        append!(I2, y.index)
        append!(D, y.data)
    end
    NDSparse(I,D)
end

function _mapslices_itable!(f, output, x, iter, iterdims, start)
    idx = Any[Colon() for v in columns(x.index)]
    I = output.index
    D = output.data
    initdims = length(iterdims)

    I1 = Columns(getsubfields(columns(I), 1:initdims)) # filled from existing table
    I2 = Columns(getsubfields(columns(I), initdims+1:fieldcount(typeof(columns(I))))) # filled from output tables

    for i = start:length(iter)
        if i != 1 && roweq(iter, i-1, i) # We've already visited this slice
            continue
        end
        for j in 1:length(iterdims)
            d = iterdims[j]
            idx[d] = iter[i][j]
        end
        if length(idx) == length(iterdims)
            idx[end] = vcat(idx[end])
        end
        subtable = x[idx...]
        y = f(subtable)
        n = length(y)

        foreach((x,y)->append_n!(x,y,n), columns(I1), iter[i])
        append!(I2, y.index)
        append!(D, y.data)
    end
    NDSparse(I,D)
end

function _flatten!(others, vecvec, out_others, out_vecvec)
    for i in 1:length(others)
        vec = vecvec[i]
        try
            for x in vec
                push!(out_vecvec, x)
                pushrow!(out_others, others, i)
            end
        catch err
            # FIXME: this is slow!
            if err isa MethodError && err.f === iterate
                push!(out_vecvec, vec)
                pushrow!(out_others, others, i)
            end
        end
    end
end

"""
    flatten(t::Table, col=length(columns(t)))

Flatten `col` column which may contain a vector of vectors while repeating the other fields.
If column argument is not provided, default to last column.

# Examples:

    x = table([1,2], [[3,4], [5,6]], names=[:x, :y])
    flatten(x, 2)

    t1 = table([3,4],[5,6], names=[:a,:b])
    t2 = table([7,8], [9,10], names=[:a,:b])
    x = table([1,2], [t1, t2], names=[:x, :y]);
    flatten(x, :y)
"""
function flatten(t::IndexedTable, col=length(columns(t)); pkey=nothing)
    vecvec = rows(t, col)
    hasmethod(iterate, (eltype(vecvec),)) || return t
    everythingbut = excludecols(t, col)

    order_others = Int[colindex(t, everythingbut)...]
    order_vecvec = Int[colindex(t, col)...]

    others = rows(t, everythingbut)
    out_others = similar(others, 0)
    out_vecvec = similar(arrayof(eltype(eltype(vecvec))), 0)

    _flatten!(others, vecvec, out_others, out_vecvec)

    cols = Any[columns(out_others)...]
    cs = columns(out_vecvec)
    newcols = isa(cs, Tup) ? Any[cs...] : Any[cs]
    ns = colnames(out_vecvec)
    i = colindex(t, col)
    cns = convert(Array{Any}, collect(colnames(t)))
    if length(ns) == 1 && !(ns[1] isa Symbol)
        ns = [colname(t, col)]
    end
    deleteat!(cns, i)
    for (n,c) in zip(reverse(ns), reverse(newcols))
        insert!(cns, i, n)
        insert!(cols, i, c)
    end
    if pkey === nothing
        if all(p -> p in order_others, t.pkey)
            pkey = t.pkey
        else
            pkey = []
        end
    end
    table(cols...; names=cns, pkey=pkey)
end
