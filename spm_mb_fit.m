function [dat,model,sett] = spm_mb_fit(data,varargin)
%__________________________________________________________________________
%
% Multi-Brain - Groupwise normalisation and segmentation of images
%
%__________________________________________________________________________
% Copyright (C) 2019 Wellcome Trust Centre for Neuroimaging

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

sett         = spm_mb_param('Settings',sett);
dir_res      = sett.write.dir_res;
do_gmm       = sett.do.gmm;
do_updt_aff  = sett.do.updt_aff;
do_zoom      = sett.do.zoom;
init_mu_dm   = sett.model.init_mu_dm;
K            = sett.model.K; 
nit_init     = sett.nit.init;
nit_init_mu  = sett.nit.init_mu;
nit_zm0      = sett.nit.zm;
print2screen = sett.show.print2screen;
vx           = sett.model.vx;
write_interm = sett.write.intermediate;

spm_mb_show('Clear',sett); % Clear figures

%------------------
% Decide what to learn
%------------------

N = numel(data); % Number of subjects

[sett,template_given] = spm_mb_param('SetFit',model,sett,N);

do_updt_int      = sett.do.updt_int;
do_updt_template = sett.do.updt_template;

%------------------
% Init dat
%------------------

dat  = spm_mb_io('InitDat',data,sett); 
data = [];

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

%------------------
% Get template size and orientation
%------------------

if template_given    
    dmu       = spm_mb_io('GetSize',model.shape.template);
    [mu0,Mmu] = spm_mb_io('GetData',model.shape.template);       
else
    [Mmu,dmu] = spm_mb_shape('SpecifyMean',dat,vx);
end
vxmu = sqrt(sum(Mmu(1:3,1:3).^2));

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
% Init shape and apperance model parameters
%------------------

dat = spm_mb_shape('InitDef',dat,sett);
dat = spm_mb_appearance('Init',dat,model,K,sett);

spm_mb_show('Speak','Start',sett,N,K);

%------------------
% Init template
%------------------

if template_given    
    % Shrink given template
    mu = spm_mb_shape('ShrinkTemplate',mu0,Mmu,sett);
else
    % Initial template
    [dat,mu,sett] = spm_mb_shape('InitMu',dat,K,sett);
end

% Show stuff
spm_mb_show('All',dat,mu,[],N,sett);

%------------------
% Start algorithm
%------------------

Objective          = [];
E                  = Inf;
prevt              = Inf;
te                 = spm_mb_shape('TemplateEnergy',mu,sett);
add_po_observation = true; % Add one posterior sample to UpdatePrior

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
                oE       = E; tic;                        
                [mu,dat] = spm_mb_shape('UpdateMean',dat, mu, sett);
                te       = spm_mb_shape('TemplateEnergy',mu,sett);
                dat      = spm_mb_appearance('UpdatePrior',dat, mu, sett, add_po_observation);
                E        = sum(sum(cat(2,dat.E),2),1) + te;
                t        = toc;

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
        oE  = E; tic;
        dat = spm_mb_shape('UpdateSimpleAffines',dat,mu,sett);
        dat = spm_mb_appearance('UpdatePrior',dat, mu, sett, add_po_observation);
        E   = sum(sum(cat(2,dat.E),2),1) + te;
        t   = toc;                        
        
        if print2screen > 0, fprintf('it=%i q  \t%g\t%g\t%g\n', it_init, E, t, (oE - E)/prevt); end
        prevt     = t;
        Objective = [Objective; E];        
        
        if write_interm && (do_updt_template || do_updt_int)
            % Save stuff
            save(fullfile(dir_res,'fit_spm_mb.mat'),'dat','sett','-v7.3','-nocompression')
        end          
    end
    
    % Save template
    dat = spm_mb_io('SaveTemplate',dat,mu,sett);
    
    % Show stuff
    spm_mb_show('All',dat,mu,Objective,N,sett);
end

%------------------
% Iteratively decrease the template resolution
%------------------

spm_mb_show('Speak','Iter',sett,numel(sz)); 
if print2screen > 0, tic; end
for zm=numel(sz):-1:1 % loop over zoom levels
    
    sett.gen.samp = min(max(vxmu(1),zm),5);     % coarse-to-fine sampling of observed data    
    if zm == 1, add_po_observation = false; end % do not add posterior sample to UpdatePrior when using no template zoom
    
    if template_given && ~do_updt_template
        mu = spm_mb_shape('ShrinkTemplate',mu0,Mmu,sett);
    end
    
    E0 = 0;
    if do_updt_template && (zm ~= numel(sz) || zm == 1)
        for i=1:nit_init_mu                    
            [mu,dat] = spm_mb_shape('UpdateMean',dat, mu, sett);
            dat      = spm_mb_appearance('UpdatePrior',dat, mu, sett, add_po_observation);
        end
        te = spm_mb_shape('TemplateEnergy',mu,sett);
        E0 = sum(sum(cat(2,dat.E),2),1) + te;
    end    
        
    nit_zm = nit_zm0 + (zm - 1);
    for it_zm=1:nit_zm

        % Update template                  
        [mu,dat] = spm_mb_shape('UpdateMean',dat, mu, sett);
        te       = spm_mb_shape('TemplateEnergy',mu,sett);
        dat      = spm_mb_appearance('UpdatePrior',dat, mu, sett, add_po_observation);
        E1       = sum(sum(cat(2,dat.E),2),1) + te;        
                           
        % Update affine
        dat      = spm_mb_shape('UpdateAffines',dat,mu,sett);
        dat      = spm_mb_appearance('UpdatePrior',dat, mu, sett, add_po_observation);
        E2       = sum(sum(cat(2,dat.E),2),1) + te;

        % Update template           
        [mu,dat] = spm_mb_shape('UpdateMean',dat, mu, sett);        
        dat      = spm_mb_appearance('UpdatePrior',dat, mu, sett, add_po_observation);
                
        [mu,dat] = spm_mb_shape('UpdateMean',dat, mu, sett);
        te       = spm_mb_shape('TemplateEnergy',mu,sett);
        dat      = spm_mb_appearance('UpdatePrior',dat, mu, sett, add_po_observation);
        E3       = sum(sum(cat(2,dat.E),2),1) + te;
            
        % Update velocities
        dat      = spm_mb_shape('VelocityEnergy',dat,sett);
        dat      = spm_mb_shape('UpdateVelocities',dat,mu,sett);
        dat      = spm_mb_shape('VelocityEnergy',dat,sett);
        dat      = spm_mb_appearance('UpdatePrior',dat, mu, sett, add_po_observation);        
        E4       = sum(sum(cat(2,dat.E),2),1) + te;       

        Objective = [Objective; E4];
        
        if (it_zm == nit_zm) && zm>1
            oMmu     = sett.var.Mmu;
            sett.var = spm_mb_io('CopyFields',sz(zm-1), sett.var);
            [dat,mu] = spm_mb_shape('ZoomVolumes',dat,mu,sett,oMmu);
        end

        % Update deformations
        dat = spm_mb_shape('UpdateWarps',dat,sett);  
        
        % Print stuff
        if print2screen > 0, fprintf('zm=%i it=%i\t%g\t%g\t%g\t%g\t%g\n', zm, it_zm, E0, E1, E2, E3, E4); end               
                
        if write_interm && (do_updt_template || do_updt_int)
            % Save stuff
            save(fullfile(dir_res,'fit_spm_mb.mat'),'dat','sett','-v7.3','-nocompression')
        end                
    end           
    
    % Save template
    dat = spm_mb_io('SaveTemplate',dat,mu,sett);

    % Show stuff
    spm_mb_show('All',dat,mu,Objective,N,sett);
    
    if print2screen > 0, fprintf('%g seconds\n\n', toc); tic; end               
end

% Final mean and intensity prior update
[mu,dat] = spm_mb_shape('UpdateMean',dat, mu, sett);
dat      = spm_mb_appearance('UpdatePrior',dat, mu, sett, add_po_observation);  

% Save template
dat = spm_mb_io('SaveTemplate',dat,mu,sett);

% Make model
model = spm_mb_io('MakeModel',dat,model,sett);

% Print total runtime
spm_mb_show('Speak','Finished',sett,toc(t0));
end
%==========================================================================