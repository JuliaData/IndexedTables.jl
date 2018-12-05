#-----------------------------------------------------------------------# Columns 
const TableColumns = Columns{T} where {T<:NamedTuple}

Columns(x; kw...) = Columns(Tables.columntable(x); kw...)

Tables.istable(::Type{<:TableColumns}) = true
Tables.materializer(c::TableColumns) = Columns

Tables.rowaccess(c::TableColumns) = true
Tables.rows(c::TableColumns) = c
Tables.schema(c::TableColumns) = Tables.Schema(colnames(c), Tuple(map(eltype, c.columns)))

Tables.columnaccess(c::TableColumns) = true
Tables.columns(c::TableColumns) = c.columns
# Tables.schema already defined for NamedTuple of Vectors (c.columns)

#-----------------------------------------------------------------------# IndexedTable
Tables.istable(::Type{IndexedTable{C}}) where {C<:TableColumns} = true
Tables.materializer(t::IndexedTable) = table
for f in [:rowaccess, :rows, :columnaccess, :columns, :schema]
    @eval Tables.$f(t::IndexedTable) = Tables.$f(Columns(columns(t)))
end

#-----------------------------------------------------------------------# NDSparse
# Tables.istable(::Type{NDSparse{T,D,C,V}}) where {T,D,C<:TableColumns,V<:TableColumns} = true
# Tables.materializer(t::NDSparse) = ndpsarse




