TableTraits.isiterabletable(x::NDSparse) = true

function IteratorInterfaceExtensions.getiterator(source::NDSparse)
    return rows(source)
end

function _array_factory(t,rows)
    if isa(t, TypeVar)
        return Array{Any}(undef, rows)
    elseif t <: DataValue
        return DataValueArray{eltype(t)}(rows)
    else
        return Array{t}(undef, rows)
    end
end

function ndsparse(x; idxcols=nothing, datacols=nothing, copy=false, kwargs...)
    if isiterable(x)
        source_data = collect_columns(getiterator(x))
        source_data isa Columns{<:Pair} && return ndsparse(source_data; copy=false, kwargs...)

        # For backward compatibility
        idxcols isa AbstractArray && (idxcols = Tuple(idxcols))
        datacols isa AbstractArray && (datacols = Tuple(datacols))

        if idxcols==nothing
            n = ncols(source_data)
            idxcols = (datacols==nothing) ? Between(1, n-1) : Not(datacols)
        end
        if datacols==nothing
            datacols = Not(idxcols)
        end

        hascolumns(source_data, idxcols) || error("Unknown idxcol")
        hascolumns(source_data, datacols) || error("Unknown datacol")

        idx_storage = rows(source_data, idxcols)
        data_storage = rows(source_data, datacols)

        return convert(NDSparse, idx_storage, data_storage; copy=false, kwargs...)
    elseif idxcols==nothing && datacols==nothing
        return convert(NDSparse, x, copy = copy, kwargs...)
    else
        throw(ArgumentError("x cannot be turned into an NDSparse."))
    end
end

# For backward compatibility
NDSparse(x; kwargs...) = ndsparse(x; kwargs...)

function table(rows::AbstractArray{T}; copy=false, kwargs...) where {T<:Union{Tup, Pair}}
    table(collect_columns(rows); copy=false, kwargs...)
end

function table(iter; copy=false, kwargs...)
    if TableTraits.isiterable(iter)
        table(collect_columns(getiterator(iter)); copy=false, kwargs...)
    else
        throw(ArgumentError("iter cannot be turned into a IndexedTable."))
    end
end
