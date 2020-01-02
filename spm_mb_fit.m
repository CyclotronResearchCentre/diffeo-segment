function [dat,model,sett] = spm_mb_fit(data,varargin)
% Multi-Brain - Groupwise normalisation and segmentation of images
%
% FORMAT [dat,model,sett] = spm_mb_fit(data,varargin)
%
% INPUT
% data -
%
%
% OUTPUT
% dat   -
% model -
% sett  -
%
%__________________________________________________________________________
%
%__________________________________________________________________________
% Copyright (C) 2020 Wellcome Trust Centre for Neuroimaging

% Parse input
p              = inputParser;
p.FunctionName = 'spm_mb_fit';
p.addParameter('model', struct(), @isstruct);
p.addParameter('sett',  struct(), @isstruct);
p.parse(varargin{:});
model = p.Results.model;
sett  = p.Results.sett;

% Set boundary conditions and path
spm_mb_io('SetBoundCond');
spm_mb_io('SetPath');

% Repeatable random numbers
rng('default'); rng(1);

t0 = tic;

%------------------
% Get algorithm settings
%------------------

N                = numel(data); % Number of subjects
sett             = spm_mb_param('DefaultSettings',sett);
[sett,given]     = spm_mb_param('ConditionalSettings',model,sett,N); % Decide what to learn
% TODO: Adapt ConditionalSettings to subspace (+ residual & latent precision)
print2screen = sett.show.print2screen;
write_ws     = sett.write.workspace;

dir_res          = sett.write.dir_res;
do_gmm           = sett.do.gmm;
do_updt_aff      = sett.do.updt_aff;
do_zoom          = sett.do.zoom;
init_mu_dm       = sett.model.init_mu_dm;
K                = sett.model.K; 
nit_init         = sett.nit.init;
nit_init_mu      = sett.nit.init_mu;
nit_zm0          = sett.nit.zm;
show_level       = sett.show.level;
vx               = sett.model.vx;
do_updt_int      = sett.do.updt_int;
do_updt_template = sett.do.updt_template;

spm_mb_show('Clear',sett); % Clear figures

%------------------
% Init dat
%------------------

dat  = spm_mb_io('InitDat',data,sett); 
clear data

if isempty(dir_res) 
    pth     = fileparts(dat(1).f(1).dat.fname);
    dir_res = pth; 
end

% Get number of template classes (if not using GMM)
if ~do_gmm, [~,K] = spm_mb_io('GetSize',dat(1).f); end
if template_given
    [~,K]        = spm_mb_io('GetSize',model.shape.template);
    sett.model.K = K;
end
if isscalar(sett.model.mg_ix)
    sett.model.mg_ix = repelem(1:K + 1,sett.model.mg_ix);
end

%------------------
% Read template dimensions
%------------------

if given.template    
    dmu       = spm_mb_io('GetSize',model.shape.template);
    Mmu       = spm_mb_io('GetMat',model.shape.template);   
elseif given.subspace
    dmu       = spm_mb_io('GetSize',model.shape.subspace);
    Mmu       = spm_mb_io('GetMat',model.shape.subspace);
else
    [Mmu,dmu] = spm_mb_shape('SpecifyMean',dat,vx);
end
vxmu     = sqrt(sum(Mmu(1:3,1:3).^2));
sett.Mmu = Mmu;

%------------------
% Set affine bases
%------------------

if dmu(3) == 1 % 2D
    sett.registr.B      = spm_mb_shape('AffineBases','SE(2)');
    denom_aff_tol       = N*100^3;               % smaller convergence threshold
else           % 3D
    sett.registr.B = spm_mb_shape('AffineBases','SE(3)');
    denom_aff_tol  = N*100^4;
end

%------------------
% Get zoom (multi-scale) settings
%------------------

nz       = max(ceil(log2(min(dmu(dmu~=1))) - log2(init_mu_dm)),1);
if ~do_zoom, nz = 1; end
sz       = spm_mb_param('ZoomSettings',dmu,Mmu,sett.var.v_settings,sett.var.mu_settings,nz);
sett.var = spm_mb_io('CopyFields',sz(end), sett.var);

%------------------
% Init shape model
%------------------

dat = spm_mb_shape('InitDat',dat,sett);
if given.subspace
    [dU,~,npc] = spm_mb_io('GetSize',model.shape.subspace);
    if prod(dU)*3*npc*4 > sett.gen.max_mem*1e9
        U0 = spm_mb_io('MemMapData',model.shape.subspace);
    else
        U0 = spm_mb_io('GetData',model.shape.subspace);
    end
    sett.pca.npc = npc;
end
shape = spm_mb_shape('InitModel', sett);

%----------------------
% Init apperance model
%----------------------

if ~do_gmm
    [~,K] = spm_mb_io('GetSize',dat(1).f);
end
if given.template
    mu0          = spm_mb_io('GetData',model.shape.template); 
    [~,K]        = spm_mb_io('GetSize',model.shape.template);
    sett.model.K = K;
end
dat = spm_mb_appearance('Init',dat,model,K,sett);

%--------------------------
% Init template / subspace
%--------------------------

spm_mb_show('Speak','Start',N,K,sett);

if given.subspace    
    % Shrink given subspace
    shape.U = spm_mb_shape('Shrink',U0,Mmu,sett);
end
shape = spm_mb_shape('InitSubspace', shape, sett);

if given.template    
    % Shrink given template
    shape.mu = spm_mb_shape('Shrink',mu0,Mmu,sett);
else
    % Initial template
    [dat,shape.mu,sett] = spm_mb_shape('InitTemplate',dat,K,sett);
end

spm_mb_show('All',dat,shape.mu,[],N,sett);

%------------------
% Start algorithm
%------------------

Objective = [];
E         = Inf;
prevt     = Inf;
add_po_observation = true; % Add one posterior sample to UpdatePrior

if do_updt_template, te = spm_mb_shape('TemplateEnergy',mu,sett); end

if do_updt_aff
    
    %------------------
    % Update shape (only affine) and appearance, on coarsest resolution
    %------------------
        
    sett.gen.samp = min(max(vxmu(1),numel(sz)),5); % coarse-to-fine sampling of observed data
    
    spm_mb_show('Speak','InitAff',sett);
    for it_init=1:nit_init
                               
        if do_updt_template
            for subit=1:nit_init_mu
                % Update template and intensity prior
                oE          = E; tic;                        
                [shape,dat] = spm_mb_shape('UpdateMean',dat,shape,sett);
                dat         = spm_mb_appearance('UpdatePrior',dat,shape.mu,sett);
                shape       = spm_mb_shape('SuffStatTemplate',dat,shape,sett);
                E_shape     = spm_mb_shape('ShapeEnergy',dat,shape,sett);
                E_app       = cat(2,dat.E);
                E           = sum(E_shape(:)) + sum(E_app(:));
                t           = toc;

                % Print stuff
                if print2screen > 0, fprintf('it=%i mu \t%g\t%g\t%g\n', it_init, E, t, (oE - E)/prevt); end
                prevt     = t;
                Objective = [Objective; E];               
            end
        end         
        
        if it_init > 1 && (oE - E)/denom_aff_tol < 1e-4
            % Finished rigid alignment
            break; 
        end        
        
        % Update affine
        oE    = E; tic;
        dat   = spm_mb_shape('UpdateSimpleAffines',dat,shape.mu,sett);
        dat   = spm_mb_appearance('UpdatePrior',dat, shape.mu, sett);
        E_app = cat(2,dat.E);
        E     = sum(E_shape(:)) + sum(E_app(:));
        t     = toc;        
        
        if print2screen > 0, fprintf('it=%i q  \t%g\t%g\t%g\n', it_init, E, t, (oE - E)/prevt); end
        prevt     = t;
        Objective = [Objective; E];        
        
        if write_ws && (do_updt_template || do_updt_int)
            % Save workspace (except template) 
            save(fullfile(dir_res,'fit_spm_mb.mat'), '-regexp', '^(?!(mu)$).');
        end          
        
        % Save template
        spm_mb_io('SaveTemplate',dat,mu,sett);
    end        
    
    % Show stuff
    spm_mb_show('All',dat,shape.mu,Objective,N,sett);
end

%------------------
% Iteratively decrease the template resolution
%------------------

spm_mb_show('Speak','Iter',sett,numel(sz)); 
if print2screen > 0, tic; end
for zm=numel(sz):-1:1 % loop over zoom levels
    
    sett.gen.samp = min(max(vxmu(1),zm),5);     % coarse-to-fine sampling of observed data    
    if zm == 1, add_po_observation = false; end % do not add posterior sample to UpdatePrior when using no template zoom
    
    if given.template && ~do_updt_template
        % Resize template
        shape.mu = spm_mb_shape('Shrink',mu0,Mmu,sett);
    end
    if given.subspace && ~do_updt_subspace
        % Resize template
        shape.U = spm_mb_shape('Shrink',U0,Mmu,sett);
    end
    
    if do_updt_template && (zm ~= numel(sz) || zm == 1)
        % Runs only at finest resolution
        for i=1:nit_init_mu
            % Update template, bias field and intensity model                        
            [shape,dat] = spm_mb_shape('UpdateMean',dat,shape,sett);
            dat         = spm_mb_appearance('UpdatePrior',dat,shape.mu,sett);
        end
    end    
        
    nit_zm = nit_zm0 + (zm - 1);
    for it_zm=1:nit_zm

        % Update template, bias field and intensity model
        % Might be an idea to run this multiple times                
        [shape,dat] = spm_mb_shape('UpdateMean',dat,shape,sett);
        dat         = spm_mb_appearance('UpdatePrior',dat,shape.mu,sett);     
                           
        % Update affine
        % (Might be an idea to run this less often - currently slow)
        dat         = spm_mb_shape('UpdateAffines',dat,shape,sett);
        dat         = spm_mb_appearance('UpdatePrior',dat,shape.mu,sett);

        % Update template, bias field and intensity model
        % (Might be an idea to run this multiple times)                
        [shape,dat] = spm_mb_shape('UpdateMean',dat,shape,sett);
        dat         = spm_mb_appearance('UpdatePrior',dat,shape,sett);
        [shape,dat] = spm_mb_shape('UpdateMean',dat,shape,sett);
        dat         = spm_mb_appearance('UpdatePrior',dat,shape.mu,sett);
            
        % Update velocities
        dat         = spm_mb_shape('UpdateVelocities',dat,shape,sett);
        dat         = spm_mb_appearance('UpdatePrior',dat,shape.mu,sett);      

        % Update pca
        [dat,shape] = spm_mb_shape('UpdateLatent',dat,shape,sett);
        shape       = spm_mb_shape('UpdateLatentPrecision',dat,shape,sett);
        shape       = spm_mb_shape('UpdateSubspace',dat,shape,sett);
        [dat,shape] = spm_mb_shape('OrthoSubspace',dat,shape,sett);
        shape       = spm_mb_shape('SuffStatVelocities',dat,shape,sett);
        shape       = spm_mb_shape('UpdateResidualPrecision',dat,shape,sett);
        
        % Compute energy
        Eold  = E;
        shape = spm_mb_shape('SuffStatTemplate',dat,shape,sett);
        E     = spm_mb_shape('ShapeEnergy',dat,shape,sett);
        E     = sum(E) + sum(sum(cat(2,dat.E),2),1);
        
        if (it_zm == nit_zm) && zm>1
            oMmu     = sett.var.Mmu;
            sett.var = spm_mb_io('CopyFields',sz(zm-1), sett.var);
            [dat,shape] = spm_mb_shape('ZoomVolumes',dat,shape,sett,oMmu);
        end

        % Update deformations
        dat = spm_mb_shape('UpdateWarps',dat,sett);  
        
        % Print stuff
        if print2screen > 0, fprintf('zm=%i it=%i\t%g\t%g\t%g\t%g\t%g\n', zm, it_zm, E0, E1, E2, E3, E4); end               
        Objective = [Objective; E];
                
        if write_ws && (do_updt_template || do_updt_int)
            % Save workspace (except template) 
            save(fullfile(dir_res,'fit_spm_mb.mat'), '-regexp', '^(?!(mu)$).');
        end          
        
        % Save template
        spm_mb_io('SaveTemplate',dat,mu,sett);             
    end           

    % Show stuff
    spm_mb_show('All',dat,mu,Objective,N,sett);
    
    % Show stuff
    spm_mb_show('All',dat,shape.mu,Objective,N,sett);            
end

% Final mean update
[shape,dat] = spm_mb_shape('UpdateMean',dat,shape,sett);
dat      = spm_mb_appearance('UpdatePrior',dat, mu, sett, add_po_observation);  

% Save template
spm_mb_io('SaveTemplate',shape.mu,sett);

% TODO: SaveSubspace

% Make model
model = spm_mb_io('MakeModel',dat,model,sett);

% TODO: save PCA variables in the model (residual and latent precision)

% Print total runtime
spm_mb_show('Speak','Finished',sett,toc(t0));
end
%==========================================================================