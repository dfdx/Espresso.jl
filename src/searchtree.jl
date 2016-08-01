
type SearchNode
    val
    children::Dict
end

SearchNode() = SearchNode(nothing, Dict())

typealias SearchTree SearchNode


function Base.put!(tree::SearchTree, keys::Vector, val)
    if isempty(keys)
        tree.val = val
    else
        if !haskey(tree.children, keys[1])
            tree.children[keys[1]] = SearchTree(nothing, Dict())
        end
        put!(tree.children[keys[1]], keys[2:end], val)
    end
end

function scan(tree::SearchTree, keys::Vector, key_idx::Int)
    if key_idx == length(keys)
        return (tree.val, -1)
    else
        next_key = keys[key_idx + 1]
        if haskey(tree.children, next_key)
            return scan(tree.children[next_key], keys, key_idx + 1)
        else
            (nothing, key_idx + 1)
        end
    end
end

scan(tree::SearchTree, keys::Vector) = scan(tree, keys, 0)

    
