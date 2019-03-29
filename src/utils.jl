#-----------------------------------------------------------------------# Missing/DataValue
missing_instance(::Type{Missing}) = missing
missing_instance(::Type{DataValue}) = DataValue()

_ismissing(x) = ismissing(x)
_ismissing(x::DataValue) = isna(x)

# convert type to a type that supports missing values, e.g. Int -> Union{Int, Missing}
type2missingtype(T, ::Type{Missing}) = Union{T, Missing}
type2missingtype(T, ::Type{DataValue}) = DataValue{T}
type2missingtype(T::Type{<:DataValue}, ::Type{DataValue}) = T

# convert missing type to nonmissing type, e.g. Union{Int, Missing} -> Int
missingtype2type(T) = Base.nonmissingtype(T)
missingtype2type(::Type{DataValue{T}}) where {T} = T

# e.g. Vector{Int} -> Vector{Union{Int, Missing}}
vec_missing(col, ::Type{Missing}) = convert(Vector{Union{Missing, eltype(col)}}, col)

function vec_missing(col::StringVector{T}, ::Type{Missing}) where {T}
    convert(StringVector{Union{Missing, T}}, col)
end

vec_missing(col, ::Type{DataValue}) = DataValueArray(col, falses(length(col)))
# function vec_missing(col::StringArray{T}, ::Type{DataValue}) where {T}
#     @show typeof(vec_missing(col, Missing)[end])
#     newcol = convert(Vector{Union{Missing, T}},vec_missing(col, Missing))
#     dump(newcol)
#     DataValueArray(newcol, falses(length(col)))
# end
vec_missing(col::DataValueArray, ::Type{DataValue}) = col

#-----------------------------------------------------------------------# other

fastmap(f, xs...) = map(f, xs...)
@generated function fastmap(f, xs::NTuple{N}...) where N
    args = [:(xs[$j][i])  for j in 1:fieldcount(typeof(xs))]
    :(Base.@ntuple $N i -> f($(args...)))
end

eltypes(::Type{Tuple{}}) = Tuple{}
eltypes(::Type{T}) where {T<:Tuple} =
    tuple_type_cons(eltype(tuple_type_head(T)), eltypes(tuple_type_tail(T)))
eltypes(::Type{T}) where {T<:NamedTuple} = map_params(eltype, T)
eltypes(::Type{T}) where T <: Pair = map_params(eltypes, T)
eltypes(::Type{T}) where T<:AbstractArray{S, N} where {S, N} = S
astuple(::Type{T}) where {T<:NamedTuple} = fieldstupletype(T)
astuple(::Type{T}) where {T<:Tuple} = T

# sizehint, making sure to return first argument
_sizehint!(a::Array{T,1}, n::Integer) where {T} = (sizehint!(a, n); a)
_sizehint!(a::AbstractArray, sz::Integer) = a

# argument selectors
left(x, y) = x
right(x, y) = y

# tuple and NamedTuple utilities

ith_all(i::Integer, xs::Union{Tuple, NamedTuple}) = map(x -> x[i], xs)

@generated function foreach(f, x::Union{NamedTuple, Tuple}, xs::Union{NamedTuple, Tuple}...)
    args = [:(getfield(getfield(xs, $j), i))  for j in 1:length(xs)]
    :(Base.@nexprs $(fieldcount(x)) i -> f(getfield(x, i), $(args...)); nothing)
end

@inline foreach(f, a::Pair) = (f(a.first); f(a.second))
@inline foreach(f, a::Pair, b::Pair) = (f(a.first, b.first); f(a.second, b.second))

fieldindex(x, i::Integer) = i
fieldindex(x::NamedTuple, s::Symbol) = findfirst(x->x===s, fieldnames(typeof(x)))

astuple(t::Tuple) = t

astuple(n::NamedTuple) = Tuple(n)

# optimized sortperm: pool non isbits types before calling sortperm_fast or sortperm_by

sortperm_fast(x) = sortperm(pool(x))

function append_n!(X, val, n)
    l = length(X)
    resize!(X, l+n)
    for i in (1:n) .+ l
        @inbounds X[i] = val
    end
    X
end

fieldstupletype(::Type{NamedTuple{N,T}}) where {N,T} = T
fieldstupletype(T::Type{<:Tuple}) = T

fieldtypes(x::Type) = fieldstupletype(x).parameters

function namedtuple(fields...)
    NamedTuple{fields}
end

"""
    arrayof(T)

Returns the type of `Columns` or `Vector` suitable to store
values of type T. Nested tuples beget nested Columns.
"""
Base.@pure function arrayof(S)
    T = strip_unionall(S)
    if T == Union{}
        Vector{Union{}}
    elseif T<:Tuple
        Columns{T, staticschema(Tuple{map(arrayof, fieldtypes(T))...})}
    elseif T<:NamedTuple
        if fieldcount(T) == 0
            Columns{NamedTuple{(), Tuple{}}, NamedTuple{(), Tuple{}}}
        else
            Columns{T,NamedTuple{fieldnames(T), Tuple{map(arrayof, fieldtypes(T))...}}}
        end
    elseif (T<:Union{Missing,String,WeakRefString} && Missing<:T) || T<:Union{String, WeakRefString}
        StringArray{T, 1}
    elseif T<:Pair
        Columns{T, NamedTuple{(:first, :second), Tuple{map(arrayof, T.parameters)...}}}
    elseif T <: DataValue
        DataValueArray{eltype(T)}
    else
        Vector{T}
    end
end

@inline strip_unionall_params(T::UnionAll) = strip_unionall_params(T.body)
@inline strip_unionall_params(T) = map(strip_unionall, fieldtypes(T))

Base.@pure function promote_union(T::Type)
    if isa(T, Union)
        return promote_type(T.a, promote_union(T.b))
    else
        return T
    end
end

Base.@pure function strip_unionall(T)
    if isconcretetype(T) || T == Union{}
        return T
    elseif isa(T, TypeVar)
        T.lb === Union{} && return strip_unionall(T.ub)
        return Any
    elseif T == Tuple
        return Any
    elseif T<:Tuple
        if any(x->x <: Vararg, fieldtypes(T))
            # we only keep known-length tuples
            return Any
        else
            return Tuple{strip_unionall_params(T)...}
        end
    elseif T<:NamedTuple
        if isa(T, Union)
            return promote_union(T)
        else
            return NamedTuple{fieldnames(T),
                              Tuple{strip_unionall_params(T)...}}
        end
    elseif isa(T, UnionAll)
        return Any
    elseif isa(T, Union)
        return promote_union(T)
    elseif T.abstract
        return T
    else
        return Any
    end
end

@inline _map(f, p::Pair) = f(p.first) => f(p.second)
@inline _map(f, args...) = map(f, args...)

# The following is not inferable, this is OK because the only place we use
# this doesn't need it.

function _map_params(f, T, S)
    (f(_tuple_type_head(T), _tuple_type_head(S)),
     _map_params(f, _tuple_type_tail(T), _tuple_type_tail(S))...)
end

_map_params(f, T::Type{Tuple{}},S::Type{Tuple{}}) = ()

map_params(f, ::Type{T}, ::Type{S}) where {T,S} = f(T,S)
map_params(f, ::Type{T}) where {T} = map_params((x,y)->f(x), T, T)
map_params(f, ::Type{T}) where T <: Pair{S1, S2} where {S1, S2} = Pair{f(S1), f(S2)}
@inline _tuple_type_head(::Type{T}) where {T<:Tuple} = Base.tuple_type_head(T)
@inline _tuple_type_tail(::Type{T}) where {T<:Tuple} = Base.tuple_type_tail(T)

#function map_params{N}(f, T::Type{T} where T<:Tuple{Vararg{Any,N}}, S::Type{S} where S<: Tuple{Vararg{Any,N}})
Base.@pure function map_params(f, ::Type{T}, ::Type{S}) where {T<:Tuple,S<:Tuple}
    if fieldcount(T) != fieldcount(S)
        MethodError(map_params, (typeof(f), T,S))
    end
    Tuple{_map_params(f, T,S)...}
end

_tuple_type_head(T::Type{NT}) where {NT<: NamedTuple} = fieldtype(NT, 1)

Base.@pure function _tuple_type_tail(T::Type{NT}) where NT<: NamedTuple
    Tuple{Base.argtail(fieldtypes(NT)...)...}
end

Base.@pure function map_params(f, ::Type{T}, ::Type{S}) where {T<:NamedTuple,S<:NamedTuple}
    if fieldnames(T) != fieldnames(S)
        MethodError(map_params, (T,S))
    end
    if fieldcount(T) == 0 && fieldcount(S) == 0
        return T
    end

    NamedTuple{fieldnames(T),
               map_params(f,
                          fieldstupletype(T),
                          fieldstupletype(S))}
end

@inline function concat_tup(a::NamedTuple, b::NamedTuple)
    merge(a, b)
end
@inline concat_tup(a::Tup, b::Tup) = (a..., b...)
@inline concat_tup(a::Tup, b) = (a..., b)
@inline concat_tup(a, b::Tup) = (a, b...)
@inline concat_tup(a, b) = (a..., b...)

Base.@pure function concat_tup_type(T::Type{<:Tuple}, S::Type{<:Tuple})
    Tuple{fieldtypes(T)..., fieldtypes(S)...}
end

Base.@pure function concat_tup_type(::Type{T}, ::Type{S}) where {
           T<:NamedTuple,S<:NamedTuple}
    fieldcount(T) == 0 && fieldcount(S) == 0 ?
        namedtuple() :
        namedtuple(fieldnames(T)...,
                   fieldnames(S)...){Tuple{fieldtypes(T)...,
                                           fieldtypes(S)...}}
end

Base.@pure function concat_tup_type(T::Type, S::Type)
    Tuple{T,S}
end

# check to see if array has shared data
# used in flush! to create a copy of the arrays
function isshared(x)
    try
        resize!(x, length(x))
        false
    catch err
        if err isa ErrorException && err.msg == "cannot resize array with shared data"
            return true
        else
            rethrow(err)
        end
    end
end

function getsubfields(n::NamedTuple, fields)
    fns = fieldnames(typeof(n))
    NamedTuple{(fns[fields]...,)}(n)
end
getsubfields(t::Tuple, fields) = t[fields]

# lexicographic order product iterator

product(itr) = itr
product(itrs...) = Base.Generator(reverse, Iterators.product(reverse(itrs)...))
