using Tables

Tables.AccessStyle(::Type{<:NextTable}) = Tables.ColumnAccess()
sch(x::Type{<:NamedTuple}) = x
sch(x::Type{T}) where {T <: Tuple} = NamedTuple{(Symbol("_$i") for i = 1:length(T.parameters)), T}
Tables.schema(x::NextTable) = sch(eltype(x))
Base.getproperty(x::Tuple, i::Int) = getfield(x, i)
Tables.columns(x::NextTable) = columns(x)
Tables.rows(x::NextTable) = rows(x)

table(x; kwargs...) = table(Tables.columntable(x); copy=false, kwargs...)

# IteratorInterfaceExtensions.getiterator(x::NextTable) = Tables.datavalues(Tables.rows(x))
