
# indexing.jl - low-level utils for working with indexed expressions

## utils

isref(ex::Expr) = ex.head == :ref
isref(x) = false


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


function get_vars!(ex::ExH{:(=)}, rec::Bool, result::Vector{Union{Symbol, Expr}})
    get_vars!(ex.args[1], rec, result)
    get_vars!(ex.args[2], rec, result)
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



##  forall & sum indexes

# rules:
# 1. If there's LHS, everything on LHS is forall, everything else is sum
# 2. If expression is multiplication (*, not .*), summation is implied
# 3. Otherwise (including element-wise operations and broadcasting), forall is implied


function longest_index{Idx}(idxs_list::Vector{Vector{Idx}})
    if isempty(idxs_list)
        return Symbol[]
    else
        reduce((idx1, idx2) -> length(idx1) < length(idx2) ? idx2 : idx1,
               idxs_list)
    end
end


function repeated_non_repeated(depidxs::Vector)
    counts = countdict(flatten(depidxs))
    repeated = collect(Symbol, keys(filter((idx, c) -> c > 1, counts)))
    non_repeated = collect(Symbol,
                           keys(filter((idx, c) -> c == 1, counts)))
    return repeated, non_repeated
end


function forall_sum_indices(op::Symbolic, depidxs::Vector)
    longest_idx = longest_index(depidxs)
    elem_wise = all(idx -> idx == longest_idx || isempty(idx), depidxs)
    if op == :*
        repeated, non_repeated = repeated_non_repeated(depidxs)
        return non_repeated, repeated
    elseif elem_wise
        return longest_idx, Symbol[]
    else
        # broadcasting - pass on all indices, preserving order of longest index
        all_idxs = vcat(longest_idx, flatten(Symbol, depidxs))
        return unique(all_idxs), Symbol[]
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
        depidxs = Vector[forall_indices(arg) for arg in ex.args[2:end]]
        # should we also add sum indices of dependencies?
        return forall_sum_indices(ex.args[1], depidxs)
    elseif ex.head == :.
        depidxs = Vector[forall_indices(arg) for arg in ex.args[2].args]
        return forall_sum_indices(ex.args[1], depidxs)
    else
        error("Don't know how to extract forall and sum indices from: $ex")
    end
end

forall_sum_indices(x) = (Symbol[], Symbol[])

forall_indices(op::Symbolic, depidxs::Vector) = forall_sum_indices(op, depidxs)[1]
forall_indices(x) = forall_sum_indices(x)[1]
sum_indices(op::Symbolic, depidxs::Vector) = forall_sum_indices(op, depidxs)[2]
sum_indices(x) = forall_sum_indices(x)[2]
