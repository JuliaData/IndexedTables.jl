#-----------------------------------------------------------------------# IndexedTable
Tables.istable(::Type{<:IndexedTable}) = true

Tables.materializer(t::IndexedTable) = table

Tables.columnaccess(::Type{<:IndexedTable}) = true
Tables.columns(t::IndexedTable) = Tables.columns(columns(t))

Tables.rowaccess(::Type{<:IndexedTable}) = true
Tables.rows(t::IndexedTable) = Tables.rows(rows(t))

Tables.schema(t::IndexedTable) = Tables.Schema(eltype(t))

# table(x; copy=false, kw...) = table(Tables.columntable(x); copy=copy, kw...)
