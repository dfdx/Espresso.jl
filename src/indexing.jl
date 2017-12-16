
# indexing.jl - low-level utils for working with indexed expressions
# TODO: rename since indexing isn't in focus of this package anymore

# const IDX_NAMES = [:i, :j, :k, :m, :n, :p, :q, :r, :s, :l]

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
