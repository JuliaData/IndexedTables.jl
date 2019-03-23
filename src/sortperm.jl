"""
Returns: (n, perm) where n is the number of columns in
the beginning of `cols`, `perm` is one possible permutation of those
first `n` columns.
"""
function best_perm_estimate(perms, cols)
    bestperm = nothing
    bestmatch = 0
    for p in perms
        matched_cols = 0
        l = min(length(cols), length(p.columns))
        for i in 1:l
            cols[i] != p.columns[i] && break
            matched_cols += 1
        end
        if matched_cols == length(cols)
            return (matched_cols, p.perm)
        elseif bestmatch < matched_cols
            bestmatch = matched_cols
            bestperm = p.perm
        end
    end
    return (bestmatch, bestperm)
end

function sortpermby(t, by; cache=false, return_keys=false)
    by = lowerselection(t, by)
    if !isa(by, Tuple)
        by = (by,)
    end
    canonorder = map((x, y)->y isa Pair ? 0 : x, colindex(t, by), by)
    canonorder_vec = Int[canonorder...]
    perms = permcache(t)
    matched_cols, partial_perm = best_perm_estimate(perms, canonorder_vec)

    if matched_cols == length(by)
        # first n index columns
        return return_keys ? (partial_perm, pool(compact_mem(rows(t, by)))) : partial_perm
    end

    byrows = pool(compact_mem(rows(t, by)))
    bycols = columns(byrows)
    perm = if matched_cols > 0
        nxtcol = bycols[matched_cols+1]
        p = convert(Array{UInt32}, partial_perm)
        refine_perm!(p, bycols, matched_cols,
                     rows(byrows, Tuple(1:matched_cols)),
                     nxtcol, 1, length(t))
        p
    else
        sortperm(byrows)
    end

    if cache
        cacheperm!(t, Perm(canonorder_vec, perm))
    end

    return return_keys ? (perm, byrows) : perm
end

function sortpermby(t, by::AbstractArray; cache=true)
    sortperm_fast(by)
end
