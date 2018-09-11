using Tables

Tables.istable(::Type{<:NextTable}) = true
Tables.rowaccess(::Type{<:NextTable}) = true
Tables.rows(x::NextTable) = rows(x)
Tables.columnaccess(::Type{<:NextTable}) = true
Tables.columns(x::NextTable) = columns(x)

sch(x::Type{<:NamedTuple}) = x
sch(x::Type{T}) where {T <: Tuple} = NamedTuple{(i for i = 1:fieldcount(T)), T}
Tables.schema(x::NextTable) = Tables.Schema(sch(eltype(x)))
Base.getproperty(x::Tuple, i::Int) = getfield(x, i)

function table(x::T; kwargs...) where {T}
    if Tables.istable(T)
        return table(Tables.columntable(x); copy=false, kwargs...)
    end
    y = IteratorInterfaceExtensions.getiterator(x)
    yT = typeof(y)
    if Base.isiterable(yT)
        if Base.IteratorEltype(yT) === Base.HasEltype() && eltype(y) <: NamedTuple
            return table(Tables.columns(Tables.DataValueUnwrapper(y)); copy=false, kwargs...)
        else
            # non-NamedTuple or EltypeUnknown
            return table(Tables.buildcolumns(nothing, Tables.DataValueUnwrapper(y)); copy=false, kwargs...)
        end
    end
    throw(ArgumentError("unable to construct NextTable from $T"))
end

IteratorInterfaceExtensions.getiterator(x::NextTable) = Tables.datavaluerows(rows(x))
