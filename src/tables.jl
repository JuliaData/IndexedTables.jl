using Tables, IteratorInterfaceExtensions

Tables.istable(::Type{<:NextTable}) = true
Tables.rowaccess(::Type{<:NextTable}) = true
Tables.rows(x::NextTable) = rows(x)
Tables.columnaccess(::Type{<:NextTable}) = true
Tables.columns(x::NextTable) = columns(x)

sch(x::Type{<:NamedTuple}) = x
sch(x::Type{T}) where {T <: Tuple} = NamedTuple{(i for i = 1:fieldcount(T)), T}
Tables.schema(x::NextTable) = Tables.Schema(sch(eltype(x)))
Base.getproperty(x::Tuple, i::Int) = getfield(x, i)

table(x::AbstractVector{T}; copy=false, kwargs...) where {T <: NamedTuple} = table(Tables.columntable(x); copy=copy, kwargs...)

function table(x::T; copy=false, kwargs...) where {T}
    if Tables.istable(T)
        return table(Tables.columntable(x); copy=copy, kwargs...)
    end
    it = TableTraits.isiterabletable(x)
    if it === true
        y = IteratorInterfaceExtensions.getiterator(x)
        return table(Tables.columns(Tables.DataValueUnwrapper(y)); copy=copy, kwargs...)
    elseif it === missing
        y = IteratorInterfaceExtensions.getiterator(x)
        # non-NamedTuple or EltypeUnknown
        return table(Tables.buildcolumns(nothing, Tables.DataValueUnwrapper(y)); copy=copy, kwargs...)
    end
    throw(ArgumentError("unable to construct NextTable from $(typeof(x))"))
end

IteratorInterfaceExtensions.getiterator(x::NextTable) = Tables.datavaluerows(rows(x))
IteratorInterfaceExtensions.isiterable(x::NextTable) = true
TableTraits.isiterabletable(x::NextTable) = true