"""
    stack(t, by = pkeynames(t); select = Not(by), variable = :variable, value = :value)`

Reshape a table from the wide to the long format. Columns in `by` are kept as indexing columns.
Columns in `select` are stacked. In addition to the id columns, two additional columns labeled 
`variable` and `value` are added, containing the column identifier and the stacked columns.
See also [`unstack`](@ref).

# Examples

    t = table(1:4, names = [:x], pkey=:x)
    t = pushcol(t, :xsquare, :x => x -> x^2)
    t = pushcol(t, :xcube  , :x => x -> x^3)

    stack(t)
"""
function stack(t::D, by = pkeynames(t); select = isa(t, NDSparse) ? valuenames(t) : excludecols(t, by),
    variable = :variable, value = :value) where {D<:Dataset}

    (by != pkeynames(t)) && return stack(reindex(t, by, select); variable = :variable, value = :value)

    valuecols = columns(t, select)
    valuecol = [valuecol[i] for i in 1:length(t) for valuecol in valuecols]

    labels = fieldnames(typeof(valuecols))
    labelcol = [label for i in 1:length(t) for label in labels]

    bycols = map(arg -> repeat(arg, inner = length(valuecols)), columns(t, by))
    convert(collectiontype(D), Columns(bycols), Columns((labelcol, valuecol), names = [variable, value]))
end

"""
    unstack(t, by = pkeynames(t); variable = :variable, value = :value)

Reshape a table from the long to the wide format. Columns in `by` are kept as indexing columns.
Keyword arguments `variable` and `value` denote which column contains the column identifier and
which the corresponding values.  See also [`stack`](@ref).

# Examples

    t = table(1:4, [1, 4, 9, 16], [1, 8, 27, 64], names = [:x, :xsquare, :xcube], pkey = :x);

    long = stack(t)

    unstack(long)
"""
function unstack(t::D, by = pkeynames(t); variable = :variable, value = :value) where {D<:Dataset}
    tgrp = groupby((value => identity,), t, by, select = (variable, value))
    S = eltype(colnames(t))
    cols = S.(union(columns(t, variable)))
    T = eltype(columns(t, value))
    unstack(D, Base.nonmissingtype(T), pkeys(tgrp), columns(tgrp, value), cols)
end

function unstack(::Type{D}, ::Type{T}, key, val, cols::AbstractVector{S}) where {D <:Dataset, T, S}
    dest_val = Columns(Tuple(Array{Union{T, Missing}}(undef, length(val)) for i in cols); names = cols)
    for (i, el) in enumerate(val)
        for (k, v) in el
            ismissing(columns(dest_val, S(k))[i]) || error("Repeated values with same label are not allowed")
            columns(dest_val, S(k))[i] = v
        end
    end
    convert(collectiontype(D), key, dest_val)
end
