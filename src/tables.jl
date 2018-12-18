#-----------------------------------------------------------------------# IndexedTable
Tables.istable(::Type{IndexedTable{C}}) where {C<:Columns} = Tables.istable(C)
Tables.materializer(t::IndexedTable) = table
for f in [:rowaccess, :rows, :columnaccess, :columns, :schema]
    @eval Tables.$f(t::IndexedTable) = Tables.$f(Columns(columns(t)))
end

#-----------------------------------------------------------------------# NDSparse
# Tables.istable(::Type{NDSparse{T,D,C,V}}) where {T,D,C<:TableColumns,V<:TableColumns} = true
# Tables.materializer(t::NDSparse) = ndpsarse




