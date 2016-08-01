
import Hydra: SearchTree, put!, scan, find

tree = SearchTree()
put!(tree, [:a, :b, :c], 42)
@test scan(tree, []) == (nothing, -1)
@test scan(tree, [:a]) == (nothing, -1)
@test scan(tree, [:a, :b]) == (nothing, -1)
@test scan(tree, [:a, :b, :c]) == (42, -1)

@test scan(tree, [:d]) == (nothing, 1)
@test scan(tree, [:a, :d]) == (nothing, 2)
@test scan(tree, [:a, :b, :d]) == (nothing, 3)
@test scan(tree, [:a, :b, :c, :d]) == (nothing, 4)
@test scan(tree, [:a, :b, :c, :d, :e]) == (nothing, 4)

