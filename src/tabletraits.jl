TableTraits.isiterabletable(x::Dataset) = true

function IteratorInterfaceExtensions.getiterator(source::NDSparse)
    return rows(source)
end

function ndsparse(x; idxcols=nothing, datacols=nothing, copy=false, kwargs...)
    if TableTraits.isiterable(x)
        source_data = collect_columns(IteratorInterfaceExtensions.getiterator(x))
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

NDSparse(x; kwargs...) = ndsparse(x; kwargs...)

function table(rows::AbstractArray{T}; copy=false, kwargs...) where {T<:Union{Tup, Pair}}
    table(collect_columns(rows); copy=false, kwargs...)
end

function table(iter; copy=false, kw...)
    if TableTraits.isiterable(iter)
        table(collect_columns(IteratorInterfaceExtensions.getiterator(iter)); copy=copy, kw...)
    elseif Tables.istable(typeof(iter))
        table(Tables.columntable(iter); copy=copy, kw...)
    else
        throw(ArgumentError("input satisfies neither IterableTables.jl nor Tables.jl"))
    end
end
