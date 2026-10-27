using MAT, JLD2, LinearAlgebra
include("blp_new.jl"); using .blp
d2 = matread("../build/input/public/simulation/100markets3products.mat")
ss = load("models_full/model_ss.jdl2")["model"]
X_supply = hcat(ones(ss.T*ss.J, 1), d2["Z"], d2["w"])
X_rivals = blp.compute_blp(ss)
Z_supply = hcat(ss.X, X_rivals, X_supply[:, 2:end])
dem = deepcopy(ss); dem.Omega = ones(ss.J, ss.J)
sys = blp.BLP(BLPDemand = dem, BLPSupply = blp.BLPSupply(X = X_supply, Z = Z_supply, W = inv(Z_supply'*Z_supply)))
failures = []
blp.estimate_blp_joint!(sys; Ns = 16, toler = 1e-6, iterations = 5, failures = failures)
println("failures: ", failures)
println("params: ", vec(sys.params))
