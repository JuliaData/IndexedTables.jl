## v0.6.0

- **(breaking)** `groupby` and `groupreduce` now select all but the grouped columns (as opposed to all columns) (#120)
- **(feature)** `usekey=true` keyword argument to `groupby` will cause the grouping function to be called with two arguments: the grouping key, and the selected subset of records. (#120)
- **(breaking)** leftjoin and outerjoin, operations don't speculatively create `DataValueArray` anymore. It will be created if there are some keys which do not have a corresponding match in the other table. (#121)
- **(feature)** `Not`, `Join`, `Between` and `Function` selectors have been added.

## v0.8.0

- **(breaking)** Uses new redisigned version of OnlineStats
    - **(breaking)** Does not wrap OnlineStats in Series wrapper. (#149) this means `m = reduce(Mean(), t, select=:x)` will return a `Mean` object rather than a `Series(Mean())` object. Also `value(m) == 0.45` for example, rather than `value(m) == (0.45,)`
- **(feature)** - `collect_columns` function to collect an iterator of tuples to `Columns` object. (#135)
- **(bugfix)** use `collect_columns` to implement `map`, `groupreduce` and `groupjoin` (#150) to not depend on type inference. Works in many more cases.
- **(feature)** - `view` works with logical indexes now (#134)


## v0.9.0

- **(breaking)** Switch from DataValues to Missing.  Related: `dropna` has been changed to `dropmissing`.
- **(breaking)** Depend on OnlineStatsBase rather than OnlineStats. 
