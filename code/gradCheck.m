function gradCheck(model, params)
%%%
%
% Perform gradient check.
%
% Thang Luong @ 2014, <lmthang@stanford.edu>
%
%%%
  % generate pseudo data
  if params.isBi
    srcTrainMaxLen = 5;
    srcTrainSents = cell(1, params.batchSize);
  else
    srcTrainSents = {};
  end

  tgtTrainSents = cell(1, params.batchSize);
  tgtTrainMaxLen = 5;

  for ii=1:params.batchSize
    if params.isBi
      srcLen = randi([1, srcTrainMaxLen-1]);
      srcTrainSents{ii} = randi([1, params.srcVocabSize-1], 1, srcLen);
      srcTrainSents{ii}(end+1) = params.srcEos;
    end

    tgtLen = randi([1, tgtTrainMaxLen-1]);
    tgtTrainSents{ii} = randi([1, params.tgtVocabSize-1], 1, tgtLen); 
    tgtTrainSents{ii}(end+1) = params.tgtEos;
  end

  % prepare data
  [trainData.input, trainData.inputMask, trainData.tgtOutput, trainData.srcMaxLen, trainData.tgtMaxLen, trainData.srcLens] = prepareData(srcTrainSents, tgtTrainSents, params);

  % analytic grad
  full_grad_W_emb = zeros(size(model.W_emb, 1), size(model.W_emb, 2));
  [totalCost, grad] = lstmCostGrad(model, trainData, params, 0);
  if params.isGPU
    full_grad_W_emb(:, grad.indices) = gather(grad.W_emb);
  else
    full_grad_W_emb(:, grad.indices) = grad.W_emb;
  end
  grad.W_emb = full_grad_W_emb;
  
  % empirical grad
  delta = 0.01;
  total_abs_diff = 0;
  numParams = 0;

  for ii=1:length(params.vars)
    field = params.vars{ii};
    if iscell(model.(field)) % cell
      for jj=1:length(model.(field))
        fprintf(2, '# %s{%d}, %s\n', field, jj, mat2str(size(model.(field){jj})));
        local_abs_diff = 0;
        for kk=1:numel(model.(field){jj})
          modelNew = model;
          modelNew.(field){jj}(kk) = modelNew.(field){jj}(kk) + delta;
          
          totalCost_new = lstmCostGrad(modelNew, trainData, params, 0);
          empGrad = (totalCost_new-totalCost)/delta;
          
          anaGrad = grad.(field){jj}(kk);
          abs_diff = abs(empGrad-anaGrad);
          local_abs_diff = local_abs_diff + abs_diff;
          numParams = numParams + 1;
          fprintf(2, '%10.6f\t%10.6f\tdiff=%g\n', empGrad, anaGrad, abs_diff);
        end
        total_abs_diff = total_abs_diff + local_abs_diff;
        fprintf(2, '  local_diff=%g\n', local_abs_diff);
      end
    else
      fprintf(2, '# %s, %s\n', field, mat2str(size(model.(field))));
      local_abs_diff = 0;
      for kk=1:numel(model.(field))
        modelNew = model;
        modelNew.(field)(kk) = modelNew.(field)(kk) + delta;

        totalCost_new = lstmCostGrad(modelNew, trainData, params, 0);
        empGrad = (totalCost_new-totalCost)/delta;

        anaGrad = grad.(field)(kk);
        abs_diff = abs(empGrad-anaGrad);
        local_abs_diff = local_abs_diff + abs_diff;
        fprintf(2, '%10.6f\t%10.6f\tdiff=%g\n', empGrad, anaGrad, abs_diff);
        numParams = numParams + 1;
      end
      total_abs_diff = total_abs_diff + local_abs_diff;
      fprintf(2, '  local_diff=%g\n', local_abs_diff);
    end 
  end
  
  fprintf(2, '# Num params=%d, abs_diff=%g\n', numParams, total_abs_diff);
end

%   % theta
%   [theta, decodeInfo] = struct2vec(model, params.vars);
%   numParams = length(theta);
%   fprintf(2, '# Num params=%d\n', numParams);
  
  
%grad = struct2vec(grad, params.vars);
%   empGrad = zeros(numParams, 1);
%   numSrcParams = 0;
%   for ii=1:length(model.W_src)
%     numSrcParams = numSrcParams + numel(model.W_src{ii});
%   end
%   numTgtParams = 0;
%   for ii=1:length(model.W_tgt)
%     numTgtParams = numTgtParams + numel(model.W_tgt{ii});
%   end
%   for i=1:numParams
%     thetaNew = theta;
%     thetaNew(i) = thetaNew(i) + delta;
%     [modelNew] = vec2struct(thetaNew, decodeInfo);
%     totalCost_new = lstmCostGrad(modelNew, trainData, params, 0);
%     empGrad(i) = (totalCost_new-totalCost)/delta;
%     abs_diff = abs_diff + abs(empGrad(i)-anaGrad(i));
%     local_abs_diff = local_abs_diff + abs(empGrad(i)-anaGrad(i));
%     if params.isBi
%       if i==1
%         fprintf(2, '# W_src\n');
%       end
%       if i==numSrcParams + 1
%         fprintf(2, '  local_diff=%g\n', local_abs_diff);
%         local_abs_diff = 0;
%         fprintf(2, '# W_tgt\n');
%       end
%     else
%       if i==1
%         fprintf(2, '# W_tgt\n');
%       end
%     end
%     
%     % W_soft
%     if i==numSrcParams + numTgtParams + 1
%       fprintf(2, '  local_diff=%g\n', local_abs_diff);
%       local_abs_diff = 0;
%       fprintf(2, '# W_soft [%d, %d]\n', size(model.W_soft, 1), size(model.W_soft, 2));
%     end
%     
%     % W_emb
%     if i==numSrcParams + numTgtParams + numel(model.W_soft) + 1
%       fprintf(2, '  local_diff=%g\n', local_abs_diff);
%       local_abs_diff = 0;
%       fprintf(2, '# W_emb [%d, %d]\n', size(model.W_emb, 1), size(model.W_emb, 2));
%     end
%     
%     % W_h
%     if params.softmaxDim>0
%       if i==numSrcParams + numTgtParams + numel(model.W_soft) + numel(model.W_emb) + 1
%         fprintf(2, '  local_diff=%g\n', local_abs_diff);
%         local_abs_diff = 0;
%         fprintf(2, '# W_h [%d, %d]\n', size(model.W_h, 1), size(model.W_h, 2));
%       end
%     end

%   if params.isBi
%     if params.attnFunc==0
%       if params.softmaxDim>0
%         [theta, decodeInfo] = param2stack(model.W_src, model.W_tgt, model.W_soft, model.W_emb, model.W_h);
%       else
%         [theta, decodeInfo] = param2stack(model.W_src, model.W_tgt, model.W_soft, model.W_emb);
%       end
%       
%     elseif params.attnFunc==1
%       [theta, decodeInfo] = param2stack(model.W_src, model.W_tgt, model.W_soft, model.W_emb, model.W_a);
%     elseif params.attnFunc==2
%       [theta, decodeInfo] = param2stack(model.W_src, model.W_tgt, model.W_soft, model.W_emb, model.W_a, model.W_a_tgt, model.v_a);
%     end
%   else
%     [theta, decodeInfo] = param2stack(model.W_tgt, model.W_soft, model.W_emb);
%   end


%   if params.isBi
%     if params.attnFunc==0
%       if params.softmaxDim>0
%         anaGrad =  param2stack(grad.W_src, grad.W_tgt, grad.W_soft, grad.W_emb, grad.W_h);
%       else
%         anaGrad =  param2stack(grad.W_src, grad.W_tgt, grad.W_soft, grad.W_emb);
%       end
%     elseif params.attnFunc==1
%       anaGrad =  param2stack(grad.W_src, grad.W_tgt, grad.W_soft, grad.W_emb, grad.W_a);
%     elseif params.attnFunc==2
%       anaGrad =  param2stack(grad.W_src, grad.W_tgt, grad.W_soft, grad.W_emb, grad.W_a, grad.W_a_tgt, grad.v_a);
%     end
%   else
%     anaGrad =  param2stack(grad.W_tgt, grad.W_soft, grad.W_emb);
%   end

%     if params.isBi
%       [modelNew.W_src, modelNew.W_tgt, modelNew.W_soft, modelNew.W_emb] = stack2param(thetaNew, decodeInfo);
%       if params.attnFunc==0
%         if params.softmaxDim>0
%           [modelNew.W_src, modelNew.W_tgt, modelNew.W_soft, modelNew.W_emb, modelNew.W_h] = stack2param(thetaNew, decodeInfo);
%         else
%           [modelNew.W_src, modelNew.W_tgt, modelNew.W_soft, modelNew.W_emb] = stack2param(thetaNew, decodeInfo);
%         end
%       elseif params.attnFunc==1
%         [modelNew.W_src, modelNew.W_tgt, modelNew.W_soft, modelNew.W_emb, modelNew.W_a] = stack2param(thetaNew, decodeInfo);
%       elseif params.attnFunc==2
%         [modelNew.W_src, modelNew.W_tgt, modelNew.W_soft, modelNew.W_emb, modelNew.W_a, modelNew.W_a_tgt, modelNew.v_a] = stack2param(thetaNew, decodeInfo);
%       end
%     else
%       model.W_src = [];
%       [modelNew.W_tgt, modelNew.W_soft, modelNew.W_emb] = stack2param(thetaNew, decodeInfo);
%     end
