function varargout = spm_mb_io(varargin)
%__________________________________________________________________________
%
% Functions for I/O related.
%
% FORMAT to              = spm_mb_io('CopyFields',from,to)
% FORMAT pth             = spm_mb_io('CropTemplate',pth,centre,bb)
% FORMAT [P,datn]        = spm_mb_io('GetClasses',datn,mu,sett)
% FORMAT [ict,imr1,imr2] = spm_mb_io('GetCTandMRI',dat)
% FORMAT [out,M]         = spm_mb_io('GetData',in)
% FORMAT Mat             = spm_mb_io('GetMat',fin)
% FORMAT [d,M]           = spm_mb_io('GetSize',fin)
% FORMAT s               = spm_mb_io('GetScale',fin,sett);
% FORMAT dat             = spm_mb_io('InitDat',data,sett)
% FORMAT model           = spm_mb_io('LoadModel',PthModel,sett)
% FORMAT model           = spm_mb_io('MakeModel',dat,model,sett)
% FORMAT [psi,fpth]      = spm_mb_io('SavePsiSub',datn,sett)
% FORMAT                   spm_mb_io('SaveTemplate',dat,mu,sett)
% FORMAT                   spm_mb_io('SetBoundCond')
% FORMAT fout            = spm_mb_io('SetData',fin,f)
% FORMAT                   spm_mb_io('SetPath')
% FORMAT                   spm_mb_io('WriteNii',f,img,Mmu,descrip);
%
%__________________________________________________________________________
% Copyright (C) 2019 Wellcome Trust Centre for Neuroimaging

if nargin == 0
    help spm_mb_io
    error('Not enough argument. Type ''help spm_mb_io'' for help.');
end
id = varargin{1};
varargin = varargin(2:end);
switch id
    case 'CopyFields'
        [varargout{1:nargout}] = CopyFields(varargin{:});
    case 'CropTemplate'
        [varargout{1:nargout}] = CropTemplate(varargin{:});
    case 'GetClasses'
        [varargout{1:nargout}] = GetClasses(varargin{:});
    case 'GetCTandMRI'
        [varargout{1:nargout}] = GetCTandMRI(varargin{:});
    case 'GetData'
        [varargout{1:nargout}] = GetData(varargin{:});
    case 'GetMat'
        [varargout{1:nargout}] = GetMat(varargin{:});
    case 'GetSize'
        [varargout{1:nargout}] = GetSize(varargin{:});
    case 'GetScale'
        [varargout{1:nargout}] = GetScale(varargin{:});
    case 'InitDat'
        [varargout{1:nargout}] = InitDat(varargin{:});
    case 'LoadModel'
        [varargout{1:nargout}] = LoadModel(varargin{:});
    case 'MakeModel'
        [varargout{1:nargout}] = MakeModel(varargin{:});
    case 'SavePsiSub'
        [varargout{1:nargout}] = SavePsiSub(varargin{:});
    case 'SaveTemplate'
        [varargout{1:nargout}] = SaveTemplate(varargin{:});
    case 'SetBoundCond'
        [varargout{1:nargout}] = SetBoundCond(varargin{:});
    case 'SetData'
        [varargout{1:nargout}] = SetData(varargin{:});
    case 'SetPath'
        [varargout{1:nargout}] = SetPath(varargin{:});
    case 'WriteNii'
        [varargout{1:nargout}] = WriteNii(varargin{:});
    otherwise
        help spm_mb_io
        error('Unknown function %s. Type ''help spm_mb_io'' for help.', id)
end
end
%==========================================================================

%==========================================================================
% CopyFields()
function to = CopyFields(from,to)
fn = fieldnames(from);
for i=1:numel(fn)
    to.(fn{i}) = from.(fn{i});
end
end
%==========================================================================

%==========================================================================
% CropTemplate()
function fout = CropTemplate(fin,centre,bb)
if nargin < 2, centre = []; end
if nargin < 3, bb     = 0;  end

if isscalar(bb), bb = bb*ones(2,3); end

[pth,nam,ext] = fileparts(fin);
fout          = fullfile(pth,['sv' nam ext]);    

bb = [centre - bb(1,:); centre + bb(2,:)]; % [l b d], [r f u]

V = spm_vol(fin);
for k=1:numel(V), SubVol(V(k),bb); end

spm_check_registration([fout ',1']);
end
%==========================================================================

%==========================================================================
% GetClasses()
function [P,datn] = GetClasses(datn,mu,sett)

if ~isfield(datn,'mog')
    P = GetData(datn.f);

    if nargout > 1
        % Compute subject-specific categorical cross-entropy loss between
        % segmentation and template
        msk       = all(isfinite(P),4);
        tmp       = sum(P.*mu,4) - spm_mb_shape('LSE',mu,4);
        datn.E(1) = -sum(tmp(msk(:)));
    end
else
    % Update appearance model
    [datn,P] = spm_mb_appearance('Update',datn,mu,sett);
end

if 0
    % Show stuff
    d  = size(mu);
    d  = [d 1 1];
    K  = d(4);
    nr = floor(sqrt(K));
    nc = ceil(K/nr);

    for k=1:K
        % Show template
        figure(664); subplot(nr,nc,k); imagesc(mu(:,:,ceil(d(3).*0.55),k)');
        title('mu');
        axis image xy off; drawnow

        % Show segmentation
        figure(665); subplot(nr,nc,k); imagesc(P(:,:,ceil(d(3).*0.55),k)');
        title('Seg')
        axis image xy off; drawnow
    end
end
end
%==========================================================================

%==========================================================================
function out = GetScale(in,sett)
% Return a scale for adding random numbers

% Parse function settings
run2d = sett.gen.run2d;

if isnumeric(in)
    if isa(in,'integer') || run2d
        out = ones([1,1,1,size(in,4)]);
    else
        out = zeros([1,1,1,size(in,4)]);
    end
    return;
end
if isa(in,'char')
    in = nifti(in);
end
if isa(in,'nifti')
    C   = numel(in);
    d   = size(in(1).dat,[1 2 3 4 5]);
    if d(4)>1 && C>1, error('Don''t know what to do with this image data.'); end
    d(4) = max(d(4),C);
    out  = zeros([1,1,1,d(4)]);
    if C>1
        for c=1:C
            dt1 = in(c).dat.dtype(1);
            if dt1=='I' || dt1=='U'
                out(c) = in(c).dat.scl_slope(1);
            end
        end
    else
        dt1 = in(1).dat.dtype(1);
        if dt1=='I' || dt1=='U'
            out(:) = in(1).dat.scl_slope(1);
        end
    end
    return
end
error('Unknown datatype.');
end
%==========================================================================

%==========================================================================
% GetCTandMRI()
function [ict,imri1,imri2] = GetCTandMRI(dat,sett)

% Parse function settings
ix_init = sett.model.ix_init_pop;

N          = numel(dat);
ict      = [];
imri2    = [];
ix_pop_mri = [];
for n=1:N
    if any(dat(n).is_ct == true)
        ict = [ict n];
    else
        ix_pop_mri = [ix_pop_mri dat(n).ix_pop];
        imri2    = [imri2 n];
    end
end
imri1 = imri2(ix_pop_mri == ix_init);
imri2 = imri2(ix_pop_mri ~= ix_init);
% ix_mri1 = [ix_mri1 ix_mri2];
% ix_mri2 = [];
end
%==========================================================================

%==========================================================================
% GetData()
function [out,Mn] = GetData(in)
Mn = eye(4);
if isnumeric(in)
    out = single(in);
    return
end
if isa(in,'char')
    in = nifti(in);
end
if isa(in,'nifti')
    C  = numel(in);
    d  = size(in(1).dat,[1 2 3 4 5]);
    Mn = in(1).mat;
    if C>1
        d(4) = C;
        out = zeros(d,'single');
        for m=1:C
            out(:,:,:,m) = single(in(m).dat(:,:,:,:,:));
        end
    else
        out = single(in.dat(:,:,:,:,:));
        if numel(d)>4 && d(4)==1
            out = reshape(out,[d(1:3) d(5)]);
        end
    end
    return
end
error('Unknown datatype.');
end
%==========================================================================

%==========================================================================
% GetMat()
function Mat = GetMat(fin)
if isnumeric(fin)
    Mat = eye(4);
    return;
end
if isa(fin,'char')
    fin = nifti(fin);
end
if isa(fin,'nifti')
    Mat  = fin(1).mat;
    return
end
error('Unknown datatype.');
end
%==========================================================================

%==========================================================================
% GetSize()
function [d,M] = GetSize(fin)
d = [GetDimensions(fin) 1 1 1];
M = d(4);
d = d(1:3);
end
%==========================================================================

%==========================================================================
% InitDat()
function dat = InitDat(data,sett)

% Parse function settings
do_gmm = sett.do.gmm;
run2d  = sett.gen.run2d;

% Initialise for each subject
N  = numel(data);
M0 = eye(4);
for n=1:N

    if isstruct(data(n)) && isfield(data(n),'F'), F = data(n).F;
    else,                                         F = data(n);
    end

    % Init datn.f
    if isnumeric(F) || iscell(F) && isnumeric(F{1})
        % Input F is numeric -> store as numeric

        if iscell(F)
            F = F{1};
        end
        if run2d
            % Get 2D slice from 3D data
            dat(n).f = GetSlice(F,run2d);
        else
            dat(n).f = single(F);
        end
    elseif isa(F,'nifti') || (iscell(F) && (isa(F{1},'char') || isa(F{1},'nifti')))
        % Input F is nifti (path or object) -> store as nifti

        if isa(F,'nifti')
            Nii      = F;
            dat(n).f = Nii;
        elseif iscell(F)
            if isa(F{1},'char')
                Nii      = nifti(F{1});
                dat(n).f = Nii;
            elseif isa(F{1},'nifti')
                Nii      = F{1};
                C        = numel(Nii);
                dat(n).f = nifti;
                for c=1:C
                    dat(n).f(c) = Nii(c);
                end
            end
        end

        if N == 1
            % Load nifti as numeri array into dat.F (faster)
            dat(n).f = spm_mb_io('GetData',dat(n).f);
        end
        
        if run2d
            % Get 2D slice from 3D data
            fn       = spm_mb_io('GetData',dat(n).f);
            dat(n).f = GetSlice(fn,run2d);
        end
    end

    % Get number of channels
    [~,C] = spm_mb_io('GetSize',dat(n).f);

    % Parameters
    dat(n).q   = zeros(6,1); % rigid registration parameters
    dat(n).v   = [];         % initial velocity
    dat(n).psi = [];         % nonlinear deformation
    dat(n).E   = [0 0];      % nllp(appear) nllp(v)
    if do_gmm        
        % GMM parameters
        dat(n).mog = []; % GMM parameters
        dat(n).bf  = []; % bias field (in image space)
    end

    % Orientation matrix (image voxel-to-world)
    dat(n).Mat = M0;
    dat(n).nam = [];
    matFromNii = false;
    if isa(F,'nifti') || (iscell(F) && (isa(F{1},'char') || isa(F{1},'nifti')))
        dat(n).Mat = Nii(1).mat0;
        [~,nam]    = fileparts(Nii(1).dat.fname);
        dat(n).nam = nam;
        matFromNii = true;
    end

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % Subject-level 'extras'
    %------------------------------------------------------------

    % spm_vol object    
    if ~matFromNii && (isstruct(data(n)) && isfield(data(n),'V') && ~isempty(data(n).V))        
        [~,nam]    = fileparts(dat(n).V(1).fname);
        dat(n).nam = nam;
        dat(n).Mat = dat(n).V(1).mat;        
    end
    df = spm_mb_io('GetSize',dat(n).f);
    if df(3) == 1
        vx         = sqrt(sum(dat(n).Mat(1:3,1:3).^2));
        dat(n).Mat = [diag(vx) zeros(3,1); 0 0 0 1];
    end
        
    % Do bias field (per channel)
    dat(n).do_bf = true;
    if isstruct(data(n)) && isfield(data(n),'do_bf') && ~isempty(data(n).do_bf)
        dat(n).do_bf = data(n).do_bf;
    end
    if numel(dat(n).do_bf) < C
        dat(n).do_bf = repmat(dat(n).do_bf,[1 C]);
    end

    % Do rescale with bf dc
    dat(n).do_dc = true;
    if isstruct(data(n)) && isfield(data(n),'do_dc') && ~isempty(data(n).do_dc)
        dat(n).do_dc = data(n).do_dc;    
    end

    % Intensity prior index
    dat(n).ix_pop = 1;
    if isstruct(data(n)) && isfield(data(n),'ix_pop') && ~isempty(data(n).ix_pop)
        dat(n).ix_pop = data(n).ix_pop;    
    end

    % Is CT data
    dat(n).is_ct = false;
    if isstruct(data(n)) && isfield(data(n),'is_ct') && ~isempty(data(n).is_ct)
        dat(n).is_ct = data(n).is_ct;            
    end
    if numel(dat(n).is_ct) < C
        dat(n).is_ct = repmat(dat(n).is_ct,[1 C]);
    end

    % Labels in a cell array as {nifti,cm_map}
    dat(n).labels = [];
    if isstruct(data(n)) && isfield(data(n),'labels') && ~isempty(data(n).labels) && ~isempty(data(n).labels{1})
        dat(n).labels = data(n).labels;

        if run2d
            % Get 2D slice from 3D data
            labels           = spm_mb_io('GetData',dat(n).labels{1});
            dat(n).labels{1} = GetSlice(labels,run2d);
        end
    end
end
end
%==========================================================================

%==========================================================================
% LoadModel()
function model = LoadModel(PthModel,sett)

% Parse function settings
appear_ix = sett.model.appear_ix;

model = struct;
if isempty(PthModel), return; end
if isfile(PthModel)
    var   = load(PthModel,'model');
    model = var.model;

    if isfield(model,'shape') && isfield(model.shape,'template')
        % Make sure path to template is correct
        model.shape.template = fullfile(fileparts(PthModel),model.shape.template);
    end

    if isfield(model,'appear') && isfield(model.appear,'pr')
        % Pick appearance prior
        model.appear.pr = model.appear.pr(num2str(min(appear_ix,model.appear.pr.Count)));
    end
end
end
%==========================================================================

%==========================================================================
% MakeModel()
function model = MakeModel(dat,model,sett)

% Parse function settings
do_gmm           = sett.do.gmm;
do_updt_int      = sett.do.updt_int;
do_updt_template = sett.do.updt_template;
dir_res          = sett.write.dir_res;
mg_ix            = sett.model.mg_ix;
write_model      = sett.write.model;

if isempty(dir_res)
    pth     = fileparts(dat(1).f(1).dat.fname);
    dir_res = pth;
end

if do_updt_template
    % Shape related
    f                    = fullfile('spm_mb_mu.nii');
    model.shape.template = f; % Store path to template
end

if do_updt_int && do_gmm
    % Appearance related
    p_ix = spm_mb_appearance('GetPopulationIdx',dat);
    Npop = numel(p_ix);

    model.appear       = struct('pr',[],'mg_ix',[]);
    model.appear.pr    = containers.Map;
    model.appear.mg_ix = mg_ix;
    for p=1:Npop
        n      = p_ix{p}(1);
        datn   = dat(n);
        ix_pop = datn.ix_pop;
        pr     = datn.mog.pr;

        model.appear.pr(num2str(ix_pop)) = pr;
    end
end

% Add Git SHA to model
folder_repo  = fileparts(mfilename('fullpath'));
cmd          = ['cd ' folder_repo ' ; git rev-parse HEAD'];
[status,sha] = system(cmd);
if status == 0
    % Store GIT ID (SHA) in model struct
    model.info.git_sha = sha;
else
    % Not able to retrieve SHA
    model.info.git_sha = 'unavailable';
end

% Add filenames of images used to build template
fnames = {};
for n=1:numel(dat)
    if isa(dat(n).f(1),'nifti')
        [~,nam,ext]     = fileparts(dat(n).f(1).dat.fname);
        fnames{end + 1} = [nam ext];
    end
end
model.info.fnames = char(fnames);

if write_model
    % Save model
    save(fullfile(dir_res,'spm_mb_model.mat'),'model')
end
end
%==========================================================================

%==========================================================================
% SavePsiSub()
function [psi,fpth] = SavePsiSub(datn,sett)

% Parse function settings
B       = sett.registr.B;
dir_res = sett.write.dir_res;
Mmu     = sett.var.Mmu;

d    = GetSize(datn.f);
q    = double(datn.q);
Mn   = datn.Mat;
psi1 = GetData(datn.psi);
psi  = spm_mb_shape('Compose',psi1,spm_mb_shape('Affine',d,Mmu\spm_dexpm(q,B)*Mn));
psi  = reshape(reshape(psi,[prod(d) 3])*Mmu(1:3,1:3)' + Mmu(1:3,4)',[d 1 3]);
fpth = '';
if isa(datn.psi(1),'nifti')
    to_delete   = datn.psi(1).dat.fname;
    [pth,nam,~] = fileparts(datn.f(1).dat.fname);
    if isempty(dir_res), dir_res = pth; end
    fpth        = fullfile(dir_res,['y_' nam '.nii']);

    datn.psi(1).dat.fname = fpth;
    datn.psi(1).dat.dim = [d 1 3];
    datn.psi(1).mat = datn.f(1).mat0; % For working with "imported" images;
   %datn.psi(1).mat = Mn;
    datn.psi(1).descrip = 'Deformation';
    create(datn.psi(1));
    datn.psi(1).dat(:,:,:,:,:) = psi;
    delete(to_delete);
end
end
%==========================================================================

%==========================================================================
% SaveTemplate()
function SaveTemplate(dat,mu,sett)

% Parse function settings
dir_res          = sett.write.dir_res;
do_updt_template = sett.do.updt_template;
Mmu              = sett.var.Mmu;
write_mu         = sett.write.mu;

if isempty(dir_res)
    pth     = fileparts(dat(1).f(1).dat.fname);
    dir_res = pth;
end

if ~isempty(mu) && do_updt_template
    if write_mu(1)
        % Log
        f        = fullfile(dir_res ,'spm_mb_mu.nii');
        fa       = file_array(f,size(mu),'float32',0);
        Nmu      = nifti;
        Nmu.dat  = fa;
        Nmu.mat  = Mmu;
        Nmu.mat0 = Mmu;
        Nmu.descrip = 'Template';
        create(Nmu);
        Nmu.dat(:,:,:,:) = mu;
    end

    if write_mu(2)
        % Softmax
        mu = spm_mb_shape('TemplateK1',mu,4);
        mu = exp(mu);

        f        = fullfile(dir_res ,'spm_mb_mu_softmax.nii');
        fa       = file_array(f,size(mu),'float32',0);
        Nmu      = nifti;
        Nmu.dat  = fa;
        Nmu.mat  = Mmu;
        Nmu.mat0 = Mmu;
        Nmu.descrip = 'Template (softmax)';
        create(Nmu);
        Nmu.dat(:,:,:,:) = mu;
    end
end
end
%==========================================================================

%==========================================================================
% SetBoundCond()
function SetBoundCond
spm_diffeo('bound',0);
spm_field('bound',1);
end
%==========================================================================

%==========================================================================
% SetData()
function fout = SetData(fin,f)
fout = fin;
if isnumeric(fin)
    fout = f;
    return
end
if isa(fin,'char')
    fin = nifti(fin);
end
if isa(fin,'nifti')
    M    = numel(fin);
    if M>1
        for m=1:M
            fout(m).dat(:,:,:,1,:) = f(:,:,:,m,:);
        end
    else
        fout(1).dat(:,:,:,:,:) = reshape(f,size(fout(1).dat));
    end
    return
end
end
%==========================================================================

%==========================================================================
% SetPath()
function SetPath
pth=fileparts(which('spm'));
addpath(pth);
addpath(fullfile(pth,'toolbox','Longitudinal'));
addpath(fullfile(pth,'toolbox','Shoot'));
end
%==========================================================================

%==========================================================================
% WriteNii()
function WriteNii(f,img,M,descrip)
fa       = file_array(f,size(img),'float32',0);
Nii      = nifti;
Nii.dat  = fa;
Nii.mat  = M;
Nii.mat0 = M;
Nii.descrip = descrip;
create(Nii);
Nii.dat(:,:,:,:,:,:) = img;
end
%==========================================================================

%==========================================================================
%
% Utility functions
%
%==========================================================================

%==========================================================================
% GetDimensions()
function d = GetDimensions(fin)
if isnumeric(fin)
    d = size(fin);
    d = [d 1 1];
    return
end
if isa(fin,'char')
    fin = nifti(fin);
end
if isa(fin,'nifti')
    M    = numel(fin);
    d    = size(fin(1).dat,[1 2 3 4 5]);
    if M>1
        d(4) = M;
    else
        if numel(d)>4 && d(4)==1
            d = [d(1:3) d(5)];
        end
    end
    return
end
end
%==========================================================================

%==========================================================================
% GetSlice()
function fn = GetSlice(fn,direction)
d  = size(fn);
d  = [d 1];
ix = round(d(1:3)*0.5);

if d(3) == 1, return; end

nslices = 0; % 1 + 2*nslices

if direction == 1
    fn = single(fn(ix(1) - nslices:ix(1) + nslices,:,:,:));
elseif direction == 2
    fn = single(fn(:,ix(2) - nslices:ix(2) + nslices,:,:));
elseif direction == 3
    fn = single(fn(:,:,ix(3) - nslices:ix(3) + nslices,:));
end

% Reshape
C  = d(4);
ix = 1:3;
d  = d(1:3);
fn = reshape(fn, [d(ix ~= direction) 1 + 2*nslices C]);
end
%==========================================================================

%==========================================================================
function VO = SubVol(V,bb,prefix,deg)
% Extract a subvolume
% FORMAT VO = subvol(V,bb,prefix)
% V      - SPM volume object
% bb     - bounding box
% prefix - file prefix (if empty -> overwrites)
% VO     - resized image
%
% Example:
%     V = spm_vol(spm_select(1,'image'));
%     subvol(V,[32 64 ; 1 64 ; 1 48]');
%__________________________________________________________________________
% Copyright (C) 2018 Wellcome Trust Centre for Neuroimaging
if nargin < 3, prefix = 'sv'; end
if nargin < 4, deg    = 0;     end

bb      = round(bb);
bb      = sort(bb);
bb(1,:) = max(bb(1,:),[1 1 1]);
bb(2,:) = min(bb(2,:),V.dim(1:3));

[~,~,oext] = fileparts(prefix);

VO            = V;
[pth,nam,ext] = fileparts(V.fname);
if ~isempty(oext)
    VO.fname  = prefix;
else
    VO.fname  = fullfile(pth,[prefix nam ext]);
end
VO.dim(1:3)   = diff(bb)+1;
VO.mat        = V.mat*spm_matrix((bb(1,:)-1));

VO = spm_create_vol(VO);
for z=1:VO.dim(3)
    M   = V.mat\VO.mat*spm_matrix([0 0 z]);
    img = spm_slice_vol(V,M,VO.dim(1:2),deg);
    VO  = spm_write_plane(VO,img,z);
end
end
%==========================================================================
