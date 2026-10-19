module blp

    using MAT, DataFrames, Statistics, Plots, LinearAlgebra, Optim, NLSolversBase


    struct BLPData
        T::Int
        J::Int  
        
        X::Matrix{Float64} 
        p::Matrix{Float64} 
        shares::Matrix{Float64} 
        errors::Matrix{Float64}

    end

    Base.@kwdef mutable struct BLPDemand
        

        BLPData::BLPData

        T::Int = BLPData.T
        J::Int  = BLPData.J 

        X::Matrix{Float64} = BLPData.X
        p::Matrix{Float64} = BLPData.p
        shares::Matrix{Float64} = BLPData.shares
        errors::Matrix{Float64} = BLPData.errors

        shares_0::Matrix{Float64}   = reshape(repeat(1.0 .- sum(reshape(shares, J, T), dims=1), inner=(J, 1)), (T*J, 1))

        Z::Matrix{Float64}          = Matrix{Float64}(undef, 0, 0)
        W::Matrix{Float64}          = Matrix{Float64}(undef, 0, 0)
        M::Matrix{Float64}          = Matrix{Float64}(undef, 0, 0)
        moments::Matrix{Float64}    = Matrix{Float64}(undef, 0, 0)
        k_Z::Union{Missing, Int}    = missing

        R::Int                      = size(errors)[2]
        k::Int                      = size(X)[2] + 1
        X_all::Matrix{Float64}      = hcat(X, p)
        sigma::Union{Missing, Float64}    = missing # This would usually will be a matrix          
        beta::Matrix{Float64}       = Matrix{Float64}(undef, k, 1)
        alphas::Matrix{Float64}     = Matrix{Float64}(undef, T * J, R)
        xi::Matrix{Float64}         = Matrix{Float64}(undef, T * J, 1)
        xi_real::Matrix{Float64}    = Matrix{Float64}(undef, T * J, 1)
        delta::Matrix{Float64}      = Matrix{Float64}(undef, T * J, 1)
        v::Matrix{Float64}          = Matrix{Float64}(undef, T, R)
        shares_sim::Matrix{Float64} = Matrix{Float64}(undef, T * J, 1)
        
        Var::Matrix{Float64}        = Matrix{Float64}(undef, k + 1, k + 1)
        util::Matrix{Float64}       = Matrix{Float64}(undef, T * J, R)
        choice::Matrix{Float64}     = Matrix{Float64}(undef, T * J, R)
        elas::Matrix{Float64}       = Matrix{Float64}(undef, T * J, J)
        elas_sim::Matrix{Float64}       = Matrix{Float64}(undef, T * J, J)
        markup::Matrix{Float64}     = Matrix{Float64}(undef, T * J, 1)
        markup_sim::Matrix{Float64} = Matrix{Float64}(undef, T * J, 1)
        cost::Matrix{Float64}       = Matrix{Float64}(undef, T * J, 1)
        cost_sim::Matrix{Float64}   = Matrix{Float64}(undef, T * J, 1)
        profit::Matrix{Float64}    = Matrix{Float64}(undef, T * J, 1)
        profit_sim::Matrix{Float64}= Matrix{Float64}(undef, T * J, 1)
        cs::Matrix{Float64}         = Matrix{Float64}(undef, T , 1)
        cs_sim::Matrix{Float64}     = Matrix{Float64}(undef, T , 1)
        grad::Matrix{Float64}       = Matrix{Float64}(undef, T * J , 1)
        

    end



    # Simulating the model given delta and sigma
    function simulate_BLP!(model::BLPDemand, delta, sigma; all = false, return_sim =true, return_grad= false)
        
        # For each market we compute the random utility part
        v = -exp.(sigma .* model.errors);
        alphas = model.beta[end] .+ v;
        grad = zeros(model.T*model.J, 1);

        ds_dp = zeros(model.T * model.J, model.J);
        util = zeros(model.J * model.T, model.R);
        choice = zeros(model.J * model.T, model.R);
        util_price = zeros(model.J * model.T, model.R);
        ds_dsigma = zeros(model.T * model.J, model.R);
        cs_sim = zeros(model.T, 1);
        elas = zeros(model.T * model.J, model.J);
        markup_sim = zeros(model.T * model.J, 1);

        for m_i in 1:model.T
            
            idx = (m_i - 1)* model.J + 1:m_i* model.J;
            util_price[idx, :] = model.p[idx,:] * v[m_i, :]';

            util[idx, :] .= delta[idx, :] .+ util_price[idx, :];
            choice[idx, :] .= exp.(util[idx, :]) ./ (1 .+ sum(exp.(util[idx, :]) , dims =1));

            if all
                for r_i in 1:model.R
                    pp_ = choice[idx, r_i];
                    pp = (diagm(pp_) - pp_ * pp_');
                    ds_dp[idx, :] += pp  * alphas[m_i, r_i]/model.R;
                end
                elas[idx, :] = ds_dp[idx, :] .* model.p[idx, :]' ./ model.shares[idx, :];
                markup_sim[idx, :] = - 1 ./ diag(elas[idx, :]);
                cs_sim[m_i, 1] = mean(-log.(1 .+ sum(exp.(util[idx, :]), dims = 1)) ./ alphas[[m_i],:]);
            end


            if (return_grad | all)
                ds_ddelta = zeros(model.J, model.J);
                for r_i in 1:model.R
                    pp_ = choice[idx, r_i];
                    pp = (diagm(pp_) - pp_ * pp_');
                    dd = v[m_i, r_i] .* model.errors[m_i, r_i] ;
                    ds_ddelta += pp;
                    ds_dsigma[idx, r_i] = (pp * (dd .* model.p[idx, :]));
                end
                grad[idx, :] = - ((ds_ddelta  ./ (model.R)) \ mean(ds_dsigma[idx, :], dims = 2));

            end
        end
        
        # Store all the computations in the object

        if all
            model.elas_sim = elas;
            model.markup_sim = markup_sim;
            model.cs_sim = cs_sim;
            model.cost_sim = model.p .* (1 .- model.markup_sim);
            model.profit_sim = (model.p - model.cost_sim) .* model.shares;
            model.shares_sim = mean(choice, dims = 2);
            model.grad = grad;
            model.alphas = alphas;
            model.util = util;
            model.choice = choice;
            model.delta = delta;
        end

        # Return the gradient
        if return_grad
            return grad
        end

        # Return the simulation
        if return_sim
            return mean(choice, dims = 2);
        end

    
    end

    # Fixed point algorithm
    function contraction(model, sigma_alpha; toler = 1e-10, max_iter = 10000, compute_grad = false)
        diff = 1000;
        delta = log.(model.shares) - log.(model.shares_0);
        flag = 0;
        count = 1;
        while toler < norm(diff)
            count += 1;
            shares_sim = simulate_BLP!(model, delta, sigma_alpha);
            diff = log.(model.shares) - log.(shares_sim);
            delta = delta + diff;
            if count > max_iter
                flag = -1;
                println("Reached max number of iterations"
                )
                break
                
                
            end
        end
        return delta
    end



    # Objective function with the gradient
    function gmm_fg!(F, G, model, sigma)
        delta = contraction(model, sigma)
        e_xi = model.M * delta;

        if G !== nothing
            grad_ = simulate_BLP!(model, delta, sigma, return_grad = true)
            G .= 2 * grad_' * model.Z * model.W *  model.Z' * e_xi;
        end
        if F !== nothing
            return ((model.Z' * e_xi)' * model.W  * model.Z' * e_xi)[]
        end

    end


end