#-----------------------------------------------------------------------# Columns 
const TableColumns = Columns{T} where {T<:NamedTuple}
Columns(x) = Columns(Tables.columntable(x))

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
table(x; kw...) = table(Tables.columntable(x); kw...)
Tables.materializer(t::IndexedTable) = table

for f in [:rowaccess, :rows, :columnaccess, :columns, :schema]
    @eval Tables.$f(t::IndexedTable) = Tables.$f(Columns(columns(t)))
end

#-----------------------------------------------------------------------# NDSparse
# Tables.istable(::Type{NDSparse{T,D,C,V}}) where {T,D,C<:TableColumns,V<:TableColumns} = true
# ndsparse(x; kw...) = ndsparse()  # What should be index cols vs. data cols?
# Tables.materializer(t::NDSparse) = ndpsarse

# for f in [:rowaccess, :rows, :columnaccess, :columns, :schema]
#     @eval Tables.$f(t::IndexedTable) = Tables.$f(Columns(columns(t)))
# end



