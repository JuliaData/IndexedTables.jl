"""
`create_dummies(t, cols; categories = Dict())`

Create a column corresponding to every categorical value present in the columns specified. `cols` is supposed be 
an array of column names or a single column name (`Symbol`) on which the dummy variables are to be created. 
The columns would have a 1 for the row with the value corresponding with the `val` as specified in the column name and 0 otherwise.
`categories` is a dictionary from column name to a vector of specific unique values.

## Examples

```jldoctest create_dummies
julia> t = table([1, 4, 9, 16], ["val1", "val1", "val2", "val2"], names = [:x, :y], pkey = :x);

julia> create_dummies(t, :y)
Table with 4 rows, 3 columns:
x   y_val1   y_val2
──────────────────
1   1        0
4   1        0
9   0        1
16  0        1

julia> t = table([1, 4, 9, 16], ["val1", "val1", "val2", "val2"], names = [:x, :y], pkey = :x);

julia> create_dummies(t, :y, categories = Dict(:y => ["val1"]))
Table with 4 rows, 3 columns:
x   y_val1 
───────────
1      1
4      1
9      0
16     0
```

"""

function create_dummies(t, cols; categories=Dict())
    for i in cols
        if haskey(categories, i)
            uniq = categories[i]
        else
            uniq = collect(keys(reduce(CountMap(), t, select = i).value))
        end
        for j in uniq
            t = setcol(t, Symbol("$(i)_$(j)"), i => x -> x == j ? Int8(1) : Int8(0))
        end
        t = popcol(t, i)
    end
    t
end

create_dummies(t, col::Symbol; categories = Dict()) = create_dummies(t, [col], categories = categories)

