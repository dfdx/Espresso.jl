
# indexing.jl - low-level utils for working with indexed expressions

const IDX_NAMES = [:i, :j, :k, :m, :n, :p, :q, :r, :s, :l]

## utils

isref(ex::Expr) = ex.head == :ref
isref(x) = false

isindexed(ex::Expr) = isref(ex) || any(isindexed, ex.args)
isindexed(x) = false


"""
Split possibly indexed variable into a name and indices. Examples:

    split_indexed(:x)         ==> (:x, [])
    split_indexed(:(x[i,j]))  ==> (:x, [:i,:j])

See also: make_indexed
"""
split_indexed(var) = (var, [])

function split_indexed(ex::Expr)
    @assert ex.head == :ref
    return convert(Symbol, ex.args[1]), ex.args[2:end]
end


"""
Make indexed variable. Examples:

    make_indexed(:x, [])       ==> :x
    make_indexed(:x, [:i,:j])  ==> :(x[i,j])

See also: split_indexed
"""
function make_indexed(vname::Symbol, vidxs::Vector)
    return isempty(vidxs) ? vname : Expr(:ref, vname, vidxs...)
end


"""Generate index names and make an indexed variable using them"""
function with_indices(x::Symbol, start_idx::Int, num_idxs::Int)
    return make_indexed(x, IDX_NAMES[start_idx:start_idx+num_idxs-1])
end

with_indices(x::Symbol, num_idxs::Int) = with_indices(x, 1, num_idxs)


## get_vars, get_var_names, get_indices

function get_vars!(x, rec::Bool, result::Vector{Union{Symbol, Expr}})
    # do nothing
end


function get_vars!(x::Symbol, rec::Bool, result::Vector{Union{Symbol, Expr}})
    push!(result, x)
end


function get_vars!(ex::Expr, rec::Bool, result::Vector{Union{Symbol, Expr}})
    get_vars!(ExH(ex), rec, result)
end


function get_vars!(ex::ExH{:ref}, rec::Bool, result::Vector{Union{Symbol, Expr}})
    push!(result, Expr(ex))
end


function get_vars!(ex::ExH{:call}, rec::Bool, result::Vector{Union{Symbol, Expr}})
    for arg in ex.args[2:end]
        if isa(arg, Symbol) || isref(arg)
            push!(result, arg)
        elseif rec
            get_vars!(arg, rec, result)
        end
    end
end


function get_vars!(ex::ExH{:.}, rec::Bool, result::Vector{Union{Symbol, Expr}})
    @assert ex.args[2].head == :tuple "Dot is only allowed in broadcasting: $ex"
    for arg in ex.args[2].args
        if isa(arg, Symbol) || isref(arg)
            push!(result, arg)
        elseif rec
            get_vars!(arg, rec, result)
        end
    end
end


function get_vars!(ex::ExH{Symbol("'")}, rec::Bool, result::Vector{Union{Symbol, Expr}})
    arg = ex.args[1]
    if isa(arg, Symbol) || isref(arg)
        push!(result, arg)
    elseif rec
        get_vars!(arg, rec, result)
    end    
end


function get_vars!(ex::ExH{:(=)}, rec::Bool, result::Vector{Union{Symbol, Expr}})
    get_vars!(ex.args[1], rec, result)
    get_vars!(ex.args[2], rec, result)
end


function get_vars!(ex::ExH{:tuple}, rec::Bool, result::Vector{Union{Symbol, Expr}})
    for arg in ex.args
        get_vars!(arg, rec, result)
    end
end


function get_vars!(ex::ExH{:block}, rec::Bool, result::Vector{Union{Symbol, Expr}})
    for subex in ex.args
        get_vars!(subex, rec, result)
    end
end


"""Get variables (`Symbol` or `Expr(:ref)`) involved in exprssion"""
function get_vars(ex::Expr; rec::Bool=false)
    result = Vector{Union{Symbol, Expr}}()
    get_vars!(ex, rec, result)
    return result
end


function get_vars(x::Symbol; rec::Bool=false)
    return Union{Symbol, Expr}[x]
end

function get_vars(x; rec::Bool=false)
    return Union{Symbol, Expr}[]
end


function get_var_names(ex; rec::Bool=false)
    vars = get_vars(ex; rec=rec)
    return [split_indexed(var)[1] for var in vars]
end


function get_indices(ex; rec::Bool=false)
    vars = get_vars(ex; rec=rec)
    return [split_indexed(var)[2] for var in vars]
end


"""
find_vars(ex; rec=true)

Same as `get_vars()`, but recursive by default
"""
find_vars(ex; rec::Bool=true) = get_vars(ex; rec=rec)
find_var_names(ex; rec::Bool=true) = get_var_names(ex; rec=rec)
find_indices(ex; rec::Bool=true) = get_indices(ex; rec=rec)


function longest_index(idxs_list::Vector{Vector{T}}) where T
    if isempty(idxs_list)
        return []
    else
        reduce((idx1, idx2) -> length(idx1) < length(idx2) ? idx2 : idx1,
               idxs_list)
    end
end


##  forall & sum indexes

# rules:
# 1. If there's LHS, everything on LHS is forall, everything else is sum
# 2. If expression is multiplication (*, not .*), summation is implied
# 3. Otherwise (including element-wise operations and broadcasting), forall is implied



function repeated_non_repeated(depidxs::Vector)
    counts = countdict(flatten(depidxs))
    repeated = collect(keys(filter((idx, c) -> c > 1, counts)))
    non_repeated = collect(keys(filter((idx, c) -> c == 1, counts)))
    return repeated, non_repeated
end


# function forall_sum_indices(op::Symbolic, depidxs::Vector)    
#     longest_idx = longest_index(depidxs)
#     elem_wise = all(idx -> idx == longest_idx || isempty(idx), depidxs)
#     if op == :*
#         repeated, non_repeated = repeated_non_repeated(depidxs)
#         return non_repeated, repeated
#     elseif elem_wise
#         return longest_idx, []
#     else
#         # broadcasting - pass on all indices, preserving order of longest index
#         # TODO: depidxs = [[:i], [:j, :n]] ->  [:j, :n, :i] - not broadcasting
#         all_idxs = vcat(longest_idx, flatten(Symbol, depidxs))
#         return unique(all_idxs), Symbol[]
#     end
# end

function forall_sum_indices(op::Symbolic, depidxs::Vector)    
    longest_idx = longest_index(depidxs)
    bcast = all(idx -> idx == longest_idx || isempty(setdiff(idx, longest_idx)), depidxs)
    if op == :*
        repeated, non_repeated = repeated_non_repeated(depidxs)
        return non_repeated, repeated
    elseif op == :length
        return [], unique(flatten(depidxs))
    elseif bcast
        return longest_idx, []
    else
        return unique(flatten(depidxs)), []
    end
end


function forall_sum_indices(ex::Expr)
    if ex.head == :(=)
        lhs_idxs_list = get_indices(ex.args[1])
        lhs_idxs = !isempty(lhs_idxs_list) ? lhs_idxs_list[1] : Symbol[]
        rhs_idxs = flatten(Symbol, get_indices(ex.args[2]))
        sum_idxs = setdiff(rhs_idxs, lhs_idxs)
        return unique(lhs_idxs), sum_idxs
    elseif ex.head == :ref
        return ex.args[2:end], Symbol[]
    elseif ex.head == :call
        depidxs = Vector{Any}[forall_indices(arg) for arg in ex.args[2:end]]
        # should we also add sum indices of dependencies?
        return forall_sum_indices(ex.args[1], depidxs)
    elseif ex.head == :.
        depidxs = Vector{Any}[forall_indices(arg) for arg in ex.args[2].args]
        return forall_sum_indices(ex.args[1], depidxs)
    else
        error("Don't know how to extract forall and sum indices from: $ex")
    end
end

forall_sum_indices(x) = ([], [])

forall_indices(op::Symbolic, depidxs::Vector) = forall_sum_indices(op, depidxs)[1]
forall_indices(x) = forall_sum_indices(x)[1]
sum_indices(op::Symbolic, depidxs::Vector) = forall_sum_indices(op, depidxs)[2]
sum_indices(x) = forall_sum_indices(x)[2]


## guards

isequality(ex) = isa(ex, Expr) && ex.head == :call && ex.args[1] == :(==)

function find_guards!(guards::Vector{Expr}, ex::Expr)
    if isequality(ex)
        push!(guards, ex)
    else
        for arg in ex.args
            find_guards!(guards, arg)
        end
    end
    return guards
end

find_guards!(guards::Vector{Expr}, x) = guards
find_guards(ex) = find_guards!(Expr[], ex)


function without_guards(ex)
    return without(ex, :(i == j); phs=[:i, :j])
end


# """
# Translates guarded expression, e.g. :(Y[i,j] = X[i] * (i == j)),
# into the unguarded one, e.g. :(Y[i, i] = X[i])
# """
# function unguarded(ex::Expr)
#     st = Dict([(grd.args[3], grd.args[2]) for grd in get_guards(ex)])
#     new_ex = without_guards(ex)
#     idxs = @view new_ex.args[1].args[2:end]
#     for i=1:length(idxs)
#         if haskey(st, idxs[i])
#             idxs[i] = st[idxs[i]]
#         end
#     end
#     return new_ex
# end


## index permutations

findperm(idxs1, idxs2) = [findfirst(idxs2, idx) for idx in idxs1]


## other utils

function without_indices(ex::Expr)
    vars = findex(:(X[IX...]), ex; phs=[:X, :IX])
    st = Dict(var => var.args[1] for var in vars)
    return subs(ex, st)
end

without_indices(x) = x




# index replacement

"""
Given a set of existing indices and current position of iterator,
find the next index not in the set.
"""
function next_index(existing::Set{T}, pos::Int) where T
    while pos <= length(IDX_NAMES) && in(IDX_NAMES[pos], existing)
        pos += 1
    end
    if pos <= length(IDX_NAMES)
        return IDX_NAMES[pos], pos + 1
    else
        throw(BoundsError("IDX_NAMES"))
    end
end


function next_indices(existing::Set{T}, pos::Int, count::Int) where T
    new_indices = Array{Symbol}(0)
    for i=1:count
        new_idx, pos = next_index(existing, pos)
        push!(new_indices, new_idx)
    end
    return new_indices
end


"""
Given a set of existing indicies and possible duplicates, find for each duplicate
a replacement - index from IDX_NAMES that is not used yet.
"""
function index_replacements(existing::Set{T}, maybedups::Vector{T}) where T
    repls = Dict{Symbol,Symbol}()
    pos = 1
    for idx in maybedups
        # maybedups should also be included in existing index set
        all_existing = union(existing, Set(maybedups), Set(keys(repls)))
        if in(idx, existing) && !in(idx, keys(repls))
            repls[idx], pos = next_index(all_existing, pos)
        end
    end
    return repls
end
