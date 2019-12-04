function res = spm_mb_output(dat,mu,sett)
%__________________________________________________________________________
%
% Write output from groupwise normalisation and segmentation of images.
%
%__________________________________________________________________________
% Copyright (C) 2019 Wellcome Trust Centre for Neuroimaging

% struct for saving paths of data written to disk
N   = numel(dat);
cl  = cell(N,1);
res = struct('bf',cl,'im',cl,'imc',cl,'c',cl,'y',cl,'iy',cl,'wim',cl,'wimc',cl,'wc',cl,'mwc',cl);
for n=1:N % Loop over subjects
    res(n) = ProcessSubject(dat(n),res(n),mu,n,sett);
end
end
%==========================================================================

%==========================================================================
%
% Utility functions
%
%==========================================================================

%==========================================================================
% ProcessSubject()
function resn = ProcessSubject(datn,resn,mu,ix,sett)

% Parse function settings
B          = sett.registr.B;
dmu        = sett.var.d;
dir_res    = sett.write.dir_res;
do_infer   = sett.do.infer;
do_updt_bf = sett.do.updt_bf;
fwhm       = sett.bf.fwhm;
Mmu        = sett.var.Mmu;
reg        = sett.bf.reg;
write_bf   = sett.write.bf; % field
write_df   = sett.write.df; % forward, inverse
write_im   = sett.write.im; % image, corrected, warped, warped corrected
write_tc   = sett.write.tc; % native, warped, warped-mod

if ~(exist(dir_res,'dir') == 7)  
    mkdir(dir_res);  
end
s       = what(dir_res); % Get absolute path
dir_res = s.path;

% Get parameters
[df,C] = spm_mb_io('GetSize',datn.f);
K      = size(mu,4);
K1     = K + 1;
if isa(datn.f(1),'nifti'), [~,namn] = fileparts(datn.f(1).dat.fname);                
else,                         namn  = ['n' num2str(ix)];
end            
Mr = spm_dexpm(double(datn.q),B);
Mn = datn.Mat;                

% Integrate K1 and C into write settings
if size(write_bf,1) == 1 && C  > 1, write_bf = repmat(write_bf,[C  1]); end    
if size(write_im,1) == 1 && C  > 1, write_im = repmat(write_im,[C  1]); end   
if size(write_tc,1) == 1 && K1 > 1, write_tc = repmat(write_tc,[K1 1]); end

if (all(write_bf(:) == false) && all(write_im(:) == false) && all(write_tc(:) == false))   
    return
end

psi0 = spm_mb_io('GetData',datn.psi);

if isfield(datn,'mog') && (any(write_bf(:) == true) || any(write_im(:) == true) || any(write_tc(:) == true))    
    % Input data were intensity images
    %------------------

    % Get subject-space template (softmaxed K + 1)
    psi = spm_mb_shape('Compose',psi0,spm_mb_shape('Affine',df,Mmu\Mr*Mn));    
    mu  = spm_mb_shape('Pull1',mu,psi);
    psi = [];
    
    % Make K + 1 template
    mu = reshape(mu,[prod(df(1:3)) K]);
    mu = cat(2,mu,zeros([prod(df(1:3)) 1],'single'));        

    if do_updt_bf
        % Get bias field
        chan = spm_mb_appearance('BiasFieldStruct',datn,C,df,reg,fwhm,[],datn.bf.T);
        bf   = spm_mb_appearance('BiasField',chan,df);
    else
        bf   = ones([1 C],'single');
    end
    
    % Get image(s)
    fn      = spm_mb_io('GetData',datn.f);
    fn      = reshape(fn,[prod(df(1:3)) C]);
    fn      = spm_mb_appearance('Mask',fn);
    code    = spm_gmm_lib('obs2code', fn);
    L       = unique(code);    
    do_miss = numel(L) > 1;
    
    % GMM posterior
    m = datn.mog.po.m;
    b = datn.mog.po.b;
    V = datn.mog.po.V;
    n = datn.mog.po.n;

    % Get responsibilities
    zn = spm_mb_appearance('Responsibility',m,b,V,n,bf.*fn,mu,L,code); 
    mu = [];     

    % Get bias field modulated image data
    fn = bf.*fn;
    if do_infer && do_miss
        % Infer missing values
        sample_post = do_infer > 1;
        MU = datn.mog.po.m;    
        A  = bsxfun(@times, datn.mog.po.V, reshape(datn.mog.po.n, [1 1 K1]));            
        fn = spm_gmm_lib('InferMissing',fn,zn,{MU,A},{code,unique(code)},sample_post);        
    end

    % TODO: Possible post-processing (MRF + clean-up)


    % Make 3D        
    bf = reshape(bf,[df(1:3) C]);
    fn = reshape(fn,[df(1:3) C]);
    zn = reshape(zn,[df(1:3) K1]);

    if any(write_bf == true)
        % Write bias field
        descrip = 'Bias field (';
        pths    = {};
        for c=1:C
            if ~write_bf(c,1), continue; end
            nam  = ['bf' num2str(c) '_' namn '.nii'];
            fpth = fullfile(dir_res,nam);            
            spm_mb_io('WriteNii',fpth,bf(:,:,:,c),Mn,[descrip 'c=' num2str(c) ')']);                
            pths{end + 1} = fpth;
        end
        resn.bf = pths;
    end

    if any(write_im(:,1) == true)
        % Write image
        descrip = 'Image (';
        pths    = {};
        for c=1:C
            if ~write_im(c,1), continue; end
            nam  = ['im' num2str(c) '_' namn '.nii'];
            fpth = fullfile(dir_res,nam);            
            spm_mb_io('WriteNii',fpth,fn(:,:,:,c)./bf(:,:,:,c),Mn,[descrip 'c=' num2str(c) ')']);
            pths{end + 1} = fpth;
        end
        resn.im = pths;

        % Write image corrected
        descrip = 'Image corrected (';
        pths    = {};
        for c=1:C
            if ~write_im(c,2), continue; end
            nam  = ['imc' num2str(c) '_' namn '.nii'];
            fpth = fullfile(dir_res,nam);            
            spm_mb_io('WriteNii',fpth,fn(:,:,:,c),Mn,[descrip 'c=' num2str(c) ')']);
            pths{end + 1} = fpth;
        end
        resn.imc = pths;
    end

    if any(write_tc(:,1) == true)
        % Write segmentations
        descrip = 'Tissue (';
        pths    = {};
        for k=1:K1 
            if ~write_tc(k,1), continue; end
            nam  = ['c' num2str(k) '_' namn '.nii'];
            fpth = fullfile(dir_res,nam);            
            spm_mb_io('WriteNii',fpth,zn(:,:,:,k),Mn,[descrip 'k=' num2str(k) ')']);
            pths{end + 1} = fpth;
        end  
        resn.c = pths;
    end
else
    % Input data were segmentations
    %------------------

    zn = spm_mb_io('GetData',datn.f);
    zn = cat(4,zn,1 - sum(zn,4));
end

if any(write_df == true) || any(reshape(write_tc(:,[2 3]),[],1) == true) ||  any(reshape(write_im(:,[3 4]),[],1) == true)
    % Write forward deformation and/or normalised images
    %------------------

    % For imporved push - subsampling density in each dimension
    sd = SampDens(Mmu,Mn);

    % Get forward deformation
    psi = spm_mb_shape('Compose',psi0,spm_mb_shape('Affine',df,Mmu\Mr*Mn));    

    if df(3) == 1, psi(:,:,:,3) = 1; end % 2D

    if write_df(1)
        % Write forward deformation
        descrip   = 'Forward deformation';
        nam       = ['y_' namn '.nii'];
        fpth      = fullfile(dir_res,nam);            
        spm_mb_io('WriteNii',fpth,psi,Mn,descrip);
        resn.y = fpth;
    end  

    if isfield(datn,'mog') && any(write_im(:,3) == true)
        % Write normalised image
        descrip = 'Normalised image (';
        pths    = {};
        for c=1:C
            if ~write_im(c,3), continue; end
            nam  = ['wim' num2str(c) '_' namn '.nii'];
            fpth = fullfile(dir_res,nam);            
            img   = spm_mb_shape('Push1',fn(:,:,:,c)./bf(:,:,:,c),psi,dmu,sd);
            spm_mb_io('WriteNii',fpth,img,Mmu,[descrip 'c=' num2str(c) ')']);            
            pths{end + 1} = fpth;
        end
        resn.wim = pths;
    end

    if isfield(datn,'mog') && any(write_im(:,4) == true)
        % Write normalised image corrected
        descrip = 'Normalised image corrected (';
        pths    = {};
        for c=1:C
            if ~write_im(c,4), continue; end
            nam  = ['wimc' num2str(c) '_' namn '.nii'];
            fpth = fullfile(dir_res,nam);            
            img   = spm_mb_shape('Push1',fn(:,:,:,c),psi,dmu,sd);
            spm_mb_io('WriteNii',fpth,img,Mmu,[descrip 'c=' num2str(c) ')']);            
            pths{end + 1} = fpth;
        end
        resn.wimc = pths;
    end

    if any(write_tc(:,2) == true)
        % Write normalised segmentations
        descrip = 'Normalised tissue (';
        pths    = {};
        for k=1:K1           
            if ~write_tc(k,2), continue; end
            nam  = ['wc' num2str(k) '_' namn '.nii'];
            fpth = fullfile(dir_res,nam);            
            img   = spm_mb_shape('Push1',zn(:,:,:,k),psi,dmu,sd);
            spm_mb_io('WriteNii',fpth,img,Mmu,[descrip 'k=' num2str(k) ')']);            
            pths{end + 1} = fpth;
        end    
        resn.wc = pths;
    end  

    if any(write_tc(:,3) == true)
        % Write normalised modulated segmentations (correct?)
        descrip = 'Normalised modulated tissue (';
        pths    = {};
        for k=1:K1           
            if ~write_tc(k,3), continue; end
            nam   = ['mwc' num2str(k) '_' namn '.nii'];
            fpth  = fullfile(dir_res,nam);
            img   = spm_mb_shape('Push1',zn(:,:,:,k),psi,dmu);
            img   = img*abs(det(Mn(1:3,1:3))/det(Mmu(1:3,1:3)));
            spm_mb_io('WriteNii',fpth,img,Mmu,[descrip 'k=' num2str(k) ')']);            
            pths{end + 1} = fpth;
        end    
        resn.mwc = pths;
    end  

    if write_df(2)
        % Get inverse deformation (correct?)
        psi = spm_diffeo('invdef',psi0,dmu(1:3),eye(4),eye(4));    
        %psi = spm_extrapolate_def(psi,Mmu);
        M   = inv(Mmu\Mr*Mn);
        psi = reshape(reshape(psi,[prod(dmu) 3])*M(1:3,1:3)' + M(1:3,4)',[dmu 3]);        

        % Write inverse deformation
        descrip = 'Inverse deformation';
        nam     = ['iy_' namn '.nii'];
        fpth    = fullfile(dir_res,nam);            
        spm_mb_io('WriteNii',fpth,psi,Mmu,descrip);
        resn.iy = fpth;
    end       
end
end
%==========================================================================

%==========================================================================
% SampDens()
function sd = SampDens(Mmu,Mf)
vx_mu = sqrt(sum(Mmu(1:3,1:3).^2,1));
vx_f  = sqrt(sum( Mf(1:3,1:3).^2,1));
sd    = max(round(2.0*vx_f./vx_mu),1);
end
%==========================================================================