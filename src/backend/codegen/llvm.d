module backend.codegen.llvm;

import core.stdc.stdio;

// Tipos básicos do LLVM
alias int64_t = long;

alias LLVMBool = int;
alias LLVMContextRef = void*;
alias LLVMModuleRef = void*;
alias LLVMBuilderRef = void*;
alias LLVMValueRef = void*;
alias LLVMTypeRef = void*;
alias LLVMBasicBlockRef = void*;
alias LLVMTargetRef = void*;
alias LLVMTargetMachineRef = void*;
alias LLVMMemoryBufferRef = void*;
alias LLVMPassManagerRef = void*;
alias LLVMExecutionEngineRef = void*;
alias LLVMMCJITMemoryManagerRef = void*;
alias LLVMPassRegistryRef = void*;
alias LLVMMetadataRef = void*;
alias LLVMNamedMDNodeRef = void*;
alias LLVMValueMetadataEntry = void*;
alias LLVMAttributeRef = void*;
alias LLVMComdatRef = void*;

alias LLVMGenericValueRef = void*;
alias LLVMTargetDataRef = void*;
alias LLVMModuleProviderRef = void*;
alias LLVMDIBuilderRef = void*;

enum LLVMThreadLocalMode
{
        LLVMNotThreadLocal = 0,
        LLVMGeneralDynamicTLSModel,
        LLVMLocalDynamicTLSModel,
        LLVMInitialExecTLSModel,
        LLVMLocalExecTLSModel
};

enum LLVMCodeGenOptLevel
{
        LLVMCodeGenLevelNone = 0,
        LLVMCodeGenLevelLess,
        LLVMCodeGenLevelDefault,
        LLVMCodeGenLevelAggressive
};

enum LLVMRelocMode
{
        LLVMRelocDefault = 0,
        LLVMRelocStatic,
        LLVMRelocPIC,
        LLVMRelocDynamicNoPIC
};

enum LLVMCodeModel
{
        LLVMCodeModelDefault = 0,
        LLVMCodeModelJITDefault,
        LLVMCodeModelTiny,
        LLVMCodeModelSmall,
        LLVMCodeModelKernel,
        LLVMCodeModelMedium,
        LLVMCodeModelLarge
};

enum LLVMCodeGenFileType
{
        LLVMAssemblyFile = 0,
        LLVMObjectFile
};

// Enums para Debug Information
enum LLVMDWARFSourceLanguage
{
        LLVMDWARFSourceLanguageC89 = 0,
        LLVMDWARFSourceLanguageC,
        LLVMDWARFSourceLanguageAda83,
        LLVMDWARFSourceLanguageC_plus_plus,
        LLVMDWARFSourceLanguageCobol74,
        LLVMDWARFSourceLanguageCobol85,
        LLVMDWARFSourceLanguageFortran77,
        LLVMDWARFSourceLanguageFortran90,
        LLVMDWARFSourceLanguagePascal83,
        LLVMDWARFSourceLanguageModula2,
        LLVMDWARFSourceLanguageJava,
        LLVMDWARFSourceLanguageC99,
        LLVMDWARFSourceLanguageAda95,
        LLVMDWARFSourceLanguageFortran95,
        LLVMDWARFSourceLanguagePLI,
        LLVMDWARFSourceLanguageObjC,
        LLVMDWARFSourceLanguageObjC_plus_plus,
        LLVMDWARFSourceLanguageUPC,
        LLVMDWARFSourceLanguageD,
        LLVMDWARFSourceLanguagePython,
        LLVMDWARFSourceLanguageOpenCL,
        LLVMDWARFSourceLanguageGo,
        LLVMDWARFSourceLanguageModula3,
        LLVMDWARFSourceLanguageHaskell,
        LLVMDWARFSourceLanguageC_plus_plus_03,
        LLVMDWARFSourceLanguageC_plus_plus_11,
        LLVMDWARFSourceLanguageOCaml,
        LLVMDWARFSourceLanguageRust,
        LLVMDWARFSourceLanguageC11,
        LLVMDWARFSourceLanguageSwift,
        LLVMDWARFSourceLanguageJulia,
        LLVMDWARFSourceLanguageDylan,
        LLVMDWARFSourceLanguageC_plus_plus_14,
        LLVMDWARFSourceLanguageFortran03,
        LLVMDWARFSourceLanguageFortran08,
        LLVMDWARFSourceLanguageRenderScript,
        LLVMDWARFSourceLanguageBLISS,
        LLVMDWARFSourceLanguageMips_Assembler,
        LLVMDWARFSourceLanguageGOOGLE_RenderScript,
        LLVMDWARFSourceLanguageBORLAND_Delphi
};

enum LLVMDWARFEmissionKind
{
        LLVMDWARF_Emission_Full = 0,
        LLVMDWARF_Emission_LineTablesOnly
};

enum LLVMDIFlags
{
        LLVMDIFlagZero = 0,
        LLVMDIFlagPrivate = 1,
        LLVMDIFlagProtected = 2,
        LLVMDIFlagPublic = 3,
        LLVMDIFlagFwdDecl = 1 << 2,
        LLVMDIFlagAppleBlock = 1 << 3,
        LLVMDIFlagBlockByrefStruct = 1 << 4,
        LLVMDIFlagVirtual = 1 << 5,
        LLVMDIFlagArtificial = 1 << 6,
        LLVMDIFlagExplicit = 1 << 7,
        LLVMDIFlagPrototyped = 1 << 8,
        LLVMDIFlagObjcClassComplete = 1 << 9,
        LLVMDIFlagObjectPointer = 1 << 10,
        LLVMDIFlagVector = 1 << 11,
        LLVMDIFlagStaticMember = 1 << 12,
        LLVMDIFlagLValueReference = 1 << 13,
        LLVMDIFlagRValueReference = 1 << 14,
        LLVMDIFlagReserved = 1 << 15,
        LLVMDIFlagSingleInheritance = 1 << 16,
        LLVMDIFlagMultipleInheritance = 2 << 16,
        LLVMDIFlagVirtualInheritance = 3 << 16,
        LLVMDIFlagIntroducedVirtual = 1 << 18,
        LLVMDIFlagBitField = 1 << 19,
        LLVMDIFlagNoReturn = 1 << 20
};

enum LLVMDWARFAddressSpace
{
        LLVMDWARFAddressSpace_undefined = 0
};

// Tipos de valores
enum LLVMTypeKind
{
        LLVMVoidTypeKind = 0,
        LLVMHalfTypeKind,
        LLVMFloatTypeKind,
        LLVMDoubleTypeKind,
        LLVMX86_FP80TypeKind,
        LLVMFP128TypeKind,
        LLVMPPC_FP128TypeKind,
        LLVMLabelTypeKind,
        LLVMIntegerTypeKind,
        LLVMFunctionTypeKind,
        LLVMStructTypeKind,
        LLVMArrayTypeKind,
        LLVMPointerTypeKind,
        LLVMVectorTypeKind,
        LLVMMetadataTypeKind,
        LLVMX86_MMXTypeKind,
        LLVMTokenTypeKind,
        LLVMScalableVectorTypeKind,
        LLVMBFloatTypeKind
};

// Linkage types
enum LLVMLinkage
{
        LLVMExternalLinkage = 0,
        LLVMAvailableExternallyLinkage,
        LLVMLinkOnceAnyLinkage,
        LLVMLinkOnceODRLinkage,
        LLVMLinkOnceODRAutoHideLinkage,
        LLVMWeakAnyLinkage,
        LLVMWeakODRLinkage,
        LLVMAppendingLinkage,
        LLVMInternalLinkage,
        LLVMPrivateLinkage,
        LLVMDLLImportLinkage,
        LLVMDLLExportLinkage,
        LLVMExternalWeakLinkage,
        LLVMGhostLinkage,
        LLVMCommonLinkage,
        LLVMLinkerPrivateLinkage,
        LLVMLinkerPrivateWeakLinkage
};

// Visibility styles
enum
{
        LLVMDefaultVisibility = 0,
        LLVMHiddenVisibility,
        LLVMProtectedVisibility
};

// Calling conventions
enum
{
        LLVMCCallConv = 0,
        LLVMFastCallConv,
        LLVMColdCallConv,
        LLVMGHCCallConv,
        LLVMHiPECallConv,
        LLVMWebKitJSCallConv,
        LLVMAnyRegCallConv,
        LLVMPreserveMostCallConv,
        LLVMPreserveAllCallConv,
        LLVMSwiftCallConv,
        LLVMX86StdcallCallConv,
        LLVMX86FastcallCallConv,
        LLVMARMAPCSCallConv,
        LLVMAARPCS_VFPCCallConv,
        LLVMMSP430INTRCallConv,
        LLVMSPIRFUNCCallConv,
        LLVMSPIRKERNELCallConv,
        LLVMIntelOCLBICallConv,
        LLVMM68kRTDCallConv,
        LLVMAVRIntrCallConv,
        LLVMAVRSignalCallConv,
        LLVMAVRBuiltinCallConv,
        LLVMAVRTOSCallConv,
        LLVMAMDGPUVSCallConv,
        LLVMAMDGPUGSCallConv,
        LLVMAMDGPUPSCallConv,
        LLVMAMDGPUCallConv,
        LLVMAMDGPULSCallConv,
        LLVMAMDGPUESCallConv
};

// Predicates
enum
{
        LLVMFalse = 0,
        LLVMTrue,
        LLVMFCMP_FALSE = 0,
        LLVMFCMP_OEQ,
        LLVMFCMP_OGT,
        LLVMFCMP_OGE,
        LLVMFCMP_OLT,
        LLVMFCMP_OLE,
        LLVMFCMP_ONE,
        LLVMFCMP_ORD,
        LLVMFCMP_UNO,
        LLVMFCMP_UEQ,
        LLVMFCMP_UGT,
        LLVMFCMP_UGE,
        LLVMFCMP_ULT,
        LLVMFCMP_ULE,
        LLVMFCMP_UNE,
        LLVMFCMP_TRUE,
        LLVMICMP_EQ = 32,
        LLVMICMP_NE,
        LLVMICMP_UGT,
        LLVMICMP_UGE,
        LLVMICMP_ULT,
        LLVMICMP_ULE,
        LLVMICMP_SGT,
        LLVMICMP_SGE,
        LLVMICMP_SLT,
        LLVMICMP_SLE
};

enum LLVMIntPredicate : int
{
        LLVMIntEQ = 32,
        LLVMIntNE = 33,
        LLVMIntUGT = 34,
        LLVMIntUGE = 35,
        LLVMIntULT = 36,
        LLVMIntULE = 37,
        LLVMIntSGT = 38,
        LLVMIntSGE = 39,
        LLVMIntSLT = 40,
        LLVMIntSLE = 41
}

enum LLVMRealPredicate : int
{
        LLVMRealOEQ = 0,
        LLVMRealOGT = 1,
        LLVMRealOGE = 2,
        LLVMRealOLT = 3,
        LLVMRealOLE = 4,
        LLVMRealONE = 5,
        LLVMRealORD = 6,
        LLVMRealUNO = 7,
        LLVMRealUEQ = 8,
        LLVMRealUGT = 9,
        LLVMRealUGE = 10,
        LLVMRealULT = 11,
        LLVMRealULE = 12,
        LLVMRealUNE = 13,
}

// Attribute kinds
enum
{
        LLVMAttributeNone = 0,
        LLVMZExt,
        LSExt,
        LLVMNoReturn,
        LLVMInReg,
        LLVMStructRet,
        LLVMNoUnwind,
        LLVMNoAlias,
        LLVMByVal,
        LLVMNest,
        LLVMReadNone,
        LLVMReadOnly,
        LLVMNoInline,
        LLVMAlwaysInline,
        LLVMOptimizeForSize,
        LLVMOptimizeNone,
        LLVMStackProtect,
        LLVMStackProtectReq,
        LLVMStackProtectStrong,
        LLVMSecure,
        LLVMNoCapture,
        LLVMNoRedZone,
        LLVMNoImplicitFloat,
        LLVMMayAlias,
        LLVMCold,
        LLVMHot,
        LLVMNonLazyBind,
        LLVMDereferenceable,
        LLVMDereferenceableOrNull,
        LLVMConvergent,
        LLVMSideEffect,
        LLVMStackAlignment,
        LLVMUWTable,
        LLVMNoCFCheck
};

// OpCodes
enum LLVMOpcode
{
        LLVMRet = 1,
        LLVMBr,
        LLVMSwitch,
        LLVMIndirectBr,
        LLVMInvoke,
        LLVMUnreachable,
        LLVMAdd,
        LLVMFAdd,
        LLVMSub,
        LLVMFSub,
        LLVMMul,
        LLVMFMul,
        LLVMUDiv,
        LLVMSDiv,
        LLVMFDiv,
        LLVMURem,
        LLVMSRem,
        LLVMFRem,
        LLVMShl,
        LLVMLShr,
        LLVMAShr,
        LLVMAnd,
        LLVMOr,
        LLVMXor,
        LLVMAlloca,
        LLVMLoad,
        LLVMStore,
        LLVMGetElementPtr,
        LLVMTrunc,
        // LLVMZExt,
        LLVMSExt,
        LLVMFPToUI,
        LLVMFPToSI,
        LLVMUIToFP,
        LLVMSIToFP,
        LLVMFPTrunc,
        LLVMFPExt,
        LLVMPtrToInt,
        LLVMIntToPtr,
        LLVMBitCast,
        LLVMAddrSpaceCast,
        LLVMICmp,
        LLVMFCmp,
        LLVMPHI,
        LLVMCall,
        LLVMSelect,
        LLVMUserOp1,
        LLVMUserOp2,
        LLVMVAArg,
        LLVMExtractElement,
        LLVMInsertElement,
        LLVMShuffleVector,
        LLVMExtractValue,
        LLVMInsertValue,
        LLVMFence,
        LLVMAtomicCmpXchg,
        LLVMAtomicRMW,
        LLVMResume,
        LLVMLandingPad,
        LLVMCleanupRet,
        LLVMCatchRet,
        LLVMCatchPad,
        LLVMCleanupPad,
        LLVMCatchSwitch,
        LLVMCallBr
};

// Memory operations
enum
{
        LLVMAtomicOrderingNotAtomic = 0,
        LLVMAtomicOrderingUnordered,
        LLVMAtomicOrderingMonotonic,
        LLVMAtomicOrderingAcquire,
        LLVMAtomicOrderingRelease,
        LLVMAtomicOrderingAcquireRelease,
        LLVMAtomicOrderingSequentiallyConsistent
};

// Funções essenciais do Core
extern (C):

// Context
LLVMContextRef LLVMGetGlobalContext();
LLVMContextRef LLVMContextCreate();
void LLVMContextDispose(LLVMContextRef C);
void LLVMContextSetDiagnosticHandler(LLVMContextRef C, void function(void*, void*, int), void* Context);
void* LLVMContextGetDiagnosticContext(LLVMContextRef C);

// Módulos
LLVMModuleRef LLVMModuleCreateWithNameInContext(const(char)* Name, LLVMContextRef C);
LLVMModuleRef LLVMModuleCreateWithName(const(char)* Name);
void LLVMDisposeModule(LLVMModuleRef M);
const(char)* LLVMGetModuleIdentifier(LLVMModuleRef M, uint* Len);
void LLVMSetModuleIdentifier(LLVMModuleRef M, const(char)* Ident, uint Len);
const(char)* LLVMGetSourceFileName(LLVMModuleRef M, uint* Len);
void LLVMSetSourceFileName(LLVMModuleRef M, const(char)* Name, uint Len);
const(char)* LLVMGetDataLayout(LLVMModuleRef M);
void LLVMSetDataLayout(LLVMModuleRef M, const(char)* DataLayout);
const(char)* LLVMGetTarget(LLVMModuleRef M);
void LLVMSetTarget(LLVMModuleRef M, const(char)* Triple);
LLVMValueRef LLVMGetNamedGlobal(LLVMModuleRef M, const(char)* Name);

// Tipos
LLVMTypeRef LLVMInt1TypeInContext(LLVMContextRef C);
LLVMTypeRef LLVMInt8TypeInContext(LLVMContextRef C);
LLVMTypeRef LLVMInt16TypeInContext(LLVMContextRef C);
LLVMTypeRef LLVMInt32TypeInContext(LLVMContextRef C);
LLVMTypeRef LLVMInt64TypeInContext(LLVMContextRef C);
LLVMTypeRef LLVMInt128TypeInContext(LLVMContextRef C);
LLVMTypeRef LLVMIntTypeInContext(LLVMContextRef C, uint NumBits);
LLVMTypeRef LLVMVoidTypeInContext(LLVMContextRef C);
LLVMTypeRef LLVMHalfTypeInContext(LLVMContextRef C);
LLVMTypeRef LLVMFloatTypeInContext(LLVMContextRef C);
LLVMTypeRef LLVMDoubleTypeInContext(LLVMContextRef C);
LLVMTypeRef LLVMX86FP80TypeInContext(LLVMContextRef C);
LLVMTypeRef LLVMFP128TypeInContext(LLVMContextRef C);
LLVMTypeRef LLVMPPCFP128TypeInContext(LLVMContextRef C);
LLVMTypeRef LLVMStructTypeInContext(LLVMContextRef C, LLVMTypeRef* ElementTypes, uint ElementCount, LLVMBool Packed);
LLVMTypeRef LLVMStructCreateNamed(LLVMContextRef C, const(char)* Name);
LLVMTypeRef LLVMStructGetTypeAtIndex(LLVMTypeRef StructTy, uint i);
LLVMTypeRef LLVMArrayType(LLVMTypeRef ElementType, uint ElementCount);
LLVMTypeRef LLVMPointerType(LLVMTypeRef ElementType, uint AddressSpace);
LLVMTypeRef LLVMVectorType(LLVMTypeRef ElementType, uint ElementCount);
LLVMTypeRef LLVMFunctionType(LLVMTypeRef ReturnType, LLVMTypeRef* ParamTypes, uint ParamCount, LLVMBool IsVarArg);

// Valores
LLVMValueRef LLVMConstNull(LLVMTypeRef Ty);
LLVMValueRef LLVMConstInt(LLVMTypeRef IntTy, ulong N, LLVMBool SignExtend);
LLVMValueRef LLVMConstReal(LLVMTypeRef RealTy, double N);
LLVMValueRef LLVMConstStringInContext(LLVMContextRef C, const(char)* Str, uint Length, LLVMBool DontNullTerminate);
LLVMValueRef LLVMConstStruct(LLVMValueRef* ConstantVals, uint Count, LLVMBool Packed);
LLVMValueRef LLVMConstArray(LLVMTypeRef ElementTy, LLVMValueRef* ConstantVals, uint Count);
LLVMValueRef LLVMConstVector(LLVMValueRef* ScalarConstantVals, uint Count);
LLVMValueRef LLVMConstNull(LLVMTypeRef Ty);
LLVMValueRef LLVMConstAllOnes(LLVMTypeRef Ty);
LLVMValueRef LLVMGetUndef(LLVMTypeRef Ty);
LLVMValueRef LLVMConstPointerNull(LLVMTypeRef Ty);
LLVMBool LLVMIsConstant(LLVMValueRef Val);
LLVMBool LLVMIsNull(LLVMValueRef Val);
LLVMBool LLVMIsUndef(LLVMValueRef Val);
LLVMValueRef LLVMConstGEP2(LLVMTypeRef Ty, LLVMValueRef ConstantVal,
        LLVMValueRef* Indices, uint NumIndices);
LLVMTypeRef LLVMTypeOf(LLVMValueRef Val);
void LLVMSetLinkage(LLVMValueRef Val, LLVMLinkage Linkage);

// Builders
LLVMBuilderRef LLVMCreateBuilderInContext(LLVMContextRef C);
LLVMBuilderRef LLVMCreateBuilder();
void LLVMDisposeBuilder(LLVMBuilderRef Builder);
void LLVMPositionBuilder(LLVMBuilderRef Builder, LLVMBasicBlockRef Block, LLVMValueRef Instr);
void LLVMPositionBuilderAtEnd(LLVMBuilderRef Builder, LLVMBasicBlockRef Block);
LLVMBasicBlockRef LLVMGetInsertBlock(LLVMBuilderRef Builder);
void LLVMClearInsertionPosition(LLVMBuilderRef Builder);
void LLVMInsertIntoBuilder(LLVMBuilderRef Builder, LLVMValueRef Instr);
void LLVMInsertIntoBuilderWithName(LLVMBuilderRef Builder, LLVMValueRef Instr, const(char)* Name);
LLVMContextRef LLVMGetBuilderContext(LLVMBuilderRef Builder);

// Instruções - Aritmética
LLVMValueRef LLVMBuildAdd(LLVMBuilderRef, LLVMValueRef LHS, LLVMValueRef RHS, const(char)* Name);
LLVMValueRef LLVMBuildNSWAdd(LLVMBuilderRef, LLVMValueRef LHS, LLVMValueRef RHS, const(char)* Name);
LLVMValueRef LLVMBuildNUWAdd(LLVMBuilderRef, LLVMValueRef LHS, LLVMValueRef RHS, const(char)* Name);
LLVMValueRef LLVMBuildFAdd(LLVMBuilderRef, LLVMValueRef LHS, LLVMValueRef RHS, const(char)* Name);
LLVMValueRef LLVMBuildSub(LLVMBuilderRef, LLVMValueRef LHS, LLVMValueRef RHS, const(char)* Name);
LLVMValueRef LLVMBuildFSub(LLVMBuilderRef, LLVMValueRef LHS, LLVMValueRef RHS, const(char)* Name);
LLVMValueRef LLVMBuildMul(LLVMBuilderRef, LLVMValueRef LHS, LLVMValueRef RHS, const(char)* Name);
LLVMValueRef LLVMBuildFMul(LLVMBuilderRef, LLVMValueRef LHS, LLVMValueRef RHS, const(char)* Name);
LLVMValueRef LLVMBuildUDiv(LLVMBuilderRef, LLVMValueRef LHS, LLVMValueRef RHS, const(char)* Name);
LLVMValueRef LLVMBuildSDiv(LLVMBuilderRef, LLVMValueRef LHS, LLVMValueRef RHS, const(char)* Name);
LLVMValueRef LLVMBuildExactSDiv(LLVMBuilderRef, LLVMValueRef LHS, LLVMValueRef RHS, const(char)* Name);
LLVMValueRef LLVMBuildFDiv(LLVMBuilderRef, LLVMValueRef LHS, LLVMValueRef RHS, const(char)* Name);
LLVMValueRef LLVMBuildURem(LLVMBuilderRef, LLVMValueRef LHS, LLVMValueRef RHS, const(char)* Name);
LLVMValueRef LLVMBuildSRem(LLVMBuilderRef, LLVMValueRef LHS, LLVMValueRef RHS, const(char)* Name);
LLVMValueRef LLVMBuildFRem(LLVMBuilderRef, LLVMValueRef LHS, LLVMValueRef RHS, const(char)* Name);

// Instruções - Lógica e bitwise
LLVMValueRef LLVMBuildShl(LLVMBuilderRef, LLVMValueRef LHS, LLVMValueRef RHS, const(char)* Name);
LLVMValueRef LLVMBuildLShr(LLVMBuilderRef, LLVMValueRef LHS, LLVMValueRef RHS, const(char)* Name);
LLVMValueRef LLVMBuildAShr(LLVMBuilderRef, LLVMValueRef LHS, LLVMValueRef RHS, const(char)* Name);
LLVMValueRef LLVMBuildAnd(LLVMBuilderRef, LLVMValueRef LHS, LLVMValueRef RHS, const(char)* Name);
LLVMValueRef LLVMBuildOr(LLVMBuilderRef, LLVMValueRef LHS, LLVMValueRef RHS, const(char)* Name);
LLVMValueRef LLVMBuildXor(LLVMBuilderRef, LLVMValueRef LHS, LLVMValueRef RHS, const(char)* Name);
LLVMValueRef LLVMBuildNeg(LLVMBuilderRef, LLVMValueRef V, const(char)* Name);
LLVMValueRef LLVMBuildNSWNeg(LLVMBuilderRef, LLVMValueRef V, const(char)* Name);
LLVMValueRef LLVMBuildNUWNeg(LLVMBuilderRef, LLVMValueRef V, const(char)* Name);
LLVMValueRef LLVMBuildFNeg(LLVMBuilderRef, LLVMValueRef V, const(char)* Name);
LLVMValueRef LLVMBuildNot(LLVMBuilderRef, LLVMValueRef V, const(char)* Name);

// Instruções - Memória
LLVMValueRef LLVMBuildAlloca(LLVMBuilderRef, LLVMTypeRef Ty, const(char)* Name);
LLVMValueRef LLVMBuildArrayAlloca(LLVMBuilderRef, LLVMTypeRef Ty, LLVMValueRef Size, const(char)* Name);
LLVMValueRef LLVMBuildLoad2(LLVMBuilderRef, LLVMTypeRef Ty, LLVMValueRef PointerVal, const(char)* Name);
LLVMValueRef LLVMBuildStore(LLVMBuilderRef, LLVMValueRef Val, LLVMValueRef Ptr);
LLVMValueRef LLVMBuildGEP2(LLVMBuilderRef B, LLVMTypeRef Ty, LLVMValueRef Pointer, LLVMValueRef* Indices, uint NumIndices, const char* Name);
LLVMValueRef LLVMBuildInBoundsGEP(LLVMBuilderRef, LLVMValueRef Pointer, LLVMValueRef* Indices, uint NumIndices, const(
                char)* Name);
LLVMValueRef LLVMBuildStructGEP(LLVMBuilderRef, LLVMValueRef Pointer, uint Idx, const(char)* Name);
LLVMValueRef LLVMBuildGlobalString(LLVMBuilderRef, const(char)* Str, const(char)* Name);
LLVMValueRef LLVMBuildGlobalStringPtr(LLVMBuilderRef, const(char)* Str, const(char)* Name);

// Instruções - Conversão
LLVMValueRef LLVMBuildTrunc(LLVMBuilderRef, LLVMValueRef Val, LLVMTypeRef DestTy, const(char)* Name);
LLVMValueRef LLVMBuildZExt(LLVMBuilderRef, LLVMValueRef Val, LLVMTypeRef DestTy, const(char)* Name);
LLVMValueRef LLVMBuildSExt(LLVMBuilderRef, LLVMValueRef Val, LLVMTypeRef DestTy, const(char)* Name);
LLVMValueRef LLVMBuildFPToUI(LLVMBuilderRef, LLVMValueRef Val, LLVMTypeRef DestTy, const(char)* Name);
LLVMValueRef LLVMBuildFPToSI(LLVMBuilderRef, LLVMValueRef Val, LLVMTypeRef DestTy, const(char)* Name);
LLVMValueRef LLVMBuildUIToFP(LLVMBuilderRef, LLVMValueRef Val, LLVMTypeRef DestTy, const(char)* Name);
LLVMValueRef LLVMBuildSIToFP(LLVMBuilderRef, LLVMValueRef Val, LLVMTypeRef DestTy, const(char)* Name);
LLVMValueRef LLVMBuildFPTrunc(LLVMBuilderRef, LLVMValueRef Val, LLVMTypeRef DestTy, const(char)* Name);
LLVMValueRef LLVMBuildFPExt(LLVMBuilderRef, LLVMValueRef Val, LLVMTypeRef DestTy, const(char)* Name);
LLVMValueRef LLVMBuildPtrToInt(LLVMBuilderRef, LLVMValueRef Val, LLVMTypeRef DestTy, const(char)* Name);
LLVMValueRef LLVMBuildIntToPtr(LLVMBuilderRef, LLVMValueRef Val, LLVMTypeRef DestTy, const(char)* Name);
LLVMValueRef LLVMBuildBitCast(LLVMBuilderRef, LLVMValueRef Val, LLVMTypeRef DestTy, const(char)* Name);
LLVMValueRef LLVMBuildAddrSpaceCast(LLVMBuilderRef, LLVMValueRef Val, LLVMTypeRef DestTy, const(
                char)* Name);
LLVMValueRef LLVMBuildZExtOrBitCast(LLVMBuilderRef, LLVMValueRef Val, LLVMTypeRef DestTy, const(
                char)* Name);
LLVMValueRef LLVMBuildSExtOrBitCast(LLVMBuilderRef, LLVMValueRef Val, LLVMTypeRef DestTy, const(
                char)* Name);
LLVMValueRef LLVMBuildTruncOrBitCast(LLVMBuilderRef, LLVMValueRef Val, LLVMTypeRef DestTy, const(
                char)* Name);
LLVMValueRef LLVMBuildCast(LLVMBuilderRef, uint Op, LLVMValueRef Val, LLVMTypeRef DestTy, const(
                char)* Name);

// Instruções - Comparação
LLVMValueRef LLVMBuildICmp(LLVMBuilderRef, uint Op, LLVMValueRef LHS, LLVMValueRef RHS, const(char)* Name);
LLVMValueRef LLVMBuildFCmp(LLVMBuilderRef, uint Op, LLVMValueRef LHS, LLVMValueRef RHS, const(char)* Name);

// Instruções - Controle de fluxo
LLVMValueRef LLVMBuildPhi(LLVMBuilderRef, LLVMTypeRef Ty, const(char)* Name);
LLVMValueRef LLVMBuildCall2(LLVMBuilderRef, LLVMTypeRef Ty, LLVMValueRef Fn, LLVMValueRef* Args, uint NumArgs, const(
                char)* Name);
LLVMValueRef LLVMBuildSelect(LLVMBuilderRef, LLVMValueRef If, LLVMValueRef Then, LLVMValueRef Else, const(
                char)* Name);
LLVMValueRef LLVMBuildVAArg(LLVMBuilderRef, LLVMValueRef List, LLVMTypeRef Ty, const(char)* Name);
LLVMValueRef LLVMBuildExtractElement(LLVMBuilderRef, LLVMValueRef VecVal, LLVMValueRef Index, const(
                char)* Name);
LLVMValueRef LLVMBuildInsertElement(LLVMBuilderRef, LLVMValueRef VecVal, LLVMValueRef EltVal, LLVMValueRef Index, const(
                char)* Name);
LLVMValueRef LLVMBuildShuffleVector(LLVMBuilderRef, LLVMValueRef V1, LLVMValueRef V2, LLVMValueRef Mask, const(
                char)* Name);
LLVMValueRef LLVMBuildExtractValue(LLVMBuilderRef, LLVMValueRef AggVal, uint Index, const(char)* Name);
LLVMValueRef LLVMBuildInsertValue(LLVMBuilderRef, LLVMValueRef AggVal, LLVMValueRef EltVal, uint Index, const(
                char)* Name);

// Instruções - Retorno
LLVMValueRef LLVMBuildRetVoid(LLVMBuilderRef);
LLVMValueRef LLVMBuildRet(LLVMBuilderRef, LLVMValueRef V);
LLVMValueRef LLVMBuildAggregateRet(LLVMBuilderRef, LLVMValueRef* RetVals, uint N);
LLVMValueRef LLVMBuildBr(LLVMBuilderRef, LLVMBasicBlockRef Dest);
LLVMValueRef LLVMBuildCondBr(LLVMBuilderRef, LLVMValueRef If, LLVMBasicBlockRef Then, LLVMBasicBlockRef Else);
LLVMValueRef LLVMBuildSwitch(LLVMBuilderRef, LLVMValueRef V, LLVMBasicBlockRef Else, uint NumCases);
LLVMValueRef LLVMBuildIndirectBr(LLVMBuilderRef, LLVMValueRef Addr, uint NumDests);
LLVMValueRef LLVMBuildUnreachable(LLVMBuilderRef);

// Basic blocks
LLVMBasicBlockRef LLVMBasicBlockAsValue(LLVMBasicBlockRef BB);
LLVMBasicBlockRef LLVMValueAsBasicBlock(LLVMValueRef Val);
LLVMBool LLVMIsABasicBlock(LLVMValueRef Val);
LLVMBasicBlockRef LLVMGetEntryBasicBlock(LLVMValueRef Fn);
LLVMBasicBlockRef LLVMGetNextBasicBlock(LLVMBasicBlockRef BB);
LLVMBasicBlockRef LLVMGetPreviousBasicBlock(LLVMBasicBlockRef BB);
LLVMBasicBlockRef LLVMBasicBlockCreateInContext(LLVMContextRef C, const(char)* Name, LLVMValueRef Fn, LLVMBasicBlockRef InsertBefore);
LLVMBasicBlockRef LLVMAppendBasicBlockInContext(LLVMContextRef C, LLVMValueRef Fn, const(char)* Name);
LLVMBasicBlockRef LLVMAppendBasicBlock(LLVMValueRef Fn, const(char)* Name);
LLVMBasicBlockRef LLVMInsertBasicBlockInContext(LLVMContextRef C, LLVMBasicBlockRef BB, const(char)* Name);
LLVMBasicBlockRef LLVMInsertBasicBlock(LLVMBasicBlockRef BB, const(char)* Name);
void LLVMDeleteBasicBlock(LLVMBasicBlockRef BB);
void LLVMMoveBasicBlockBefore(LLVMBasicBlockRef BB, LLVMBasicBlockRef MovePos);
void LLVMMoveBasicBlockAfter(LLVMBasicBlockRef BB, LLVMBasicBlockRef MovePos);

// Funções
LLVMValueRef LLVMAddFunction(LLVMModuleRef M, const(char)* Name, LLVMTypeRef FunctionTy);
LLVMValueRef LLVMGetNamedFunction(LLVMModuleRef M, const(char)* Name);
LLVMValueRef LLVMGetFirstFunction(LLVMModuleRef M);
LLVMValueRef LLVMGetLastFunction(LLVMModuleRef M);
LLVMValueRef LLVMGetNextFunction(LLVMValueRef Fn);
LLVMValueRef LLVMGetPreviousFunction(LLVMValueRef Fn);
void LLVMDeleteFunction(LLVMValueRef Fn);
uint LLVMGetIntrinsicID(LLVMValueRef Fn);
uint LLVMGetFunctionCallConv(LLVMValueRef Fn);
void LLVMSetFunctionCallConv(LLVMValueRef Fn, uint CC);
const(char)* LLVMGetValueName(LLVMValueRef Val);
void LLVMSetValueName(LLVMValueRef Val, const(char)* Name);
void LLVMDumpValue(LLVMValueRef Val);

// Parâmetros
LLVMValueRef LLVMGetParam(LLVMValueRef Fn, uint Index);
LLVMValueRef LLVMGetFirstParam(LLVMValueRef Fn);
LLVMValueRef LLVMGetLastParam(LLVMValueRef Fn);
LLVMValueRef LLVMGetNextParam(LLVMValueRef Arg);
LLVMValueRef LLVMGetPreviousParam(LLVMValueRef Arg);
LLVMValueRef LLVMGetParamParent(LLVMValueRef Inst);
uint LLVMGetParamCount(LLVMValueRef Fn);

// Globais
LLVMValueRef LLVMAddGlobal(LLVMModuleRef M, LLVMTypeRef Ty, const(char)* Name);
LLVMValueRef LLVMGetNamedGlobal(LLVMModuleRef M, const(char)* Name);
LLVMValueRef LLVMGetFirstGlobal(LLVMModuleRef M);
LLVMValueRef LLVMGetLastGlobal(LLVMModuleRef M);
LLVMValueRef LLVMGetNextGlobal(LLVMValueRef GlobalVar);
LLVMValueRef LLVMGetPreviousGlobal(LLVMValueRef GlobalVar);
void LLVMDeleteGlobal(LLVMValueRef GlobalVar);
LLVMValueRef LLVMGetInitializer(LLVMValueRef GlobalVar);
void LLVMSetInitializer(LLVMValueRef GlobalVar, LLVMValueRef ConstantVal);
LLVMBool LLVMIsThreadLocal(LLVMValueRef GlobalVar);
void LLVMSetThreadLocal(LLVMValueRef GlobalVar, LLVMBool IsThreadLocal);
LLVMBool LLVMIsGlobalConstant(LLVMValueRef GlobalVar);
void LLVMSetGlobalConstant(LLVMValueRef GlobalVar, LLVMBool IsConstant);
LLVMThreadLocalMode LLVMGetThreadLocalMode(LLVMValueRef GlobalVar);
void LLVMSetThreadLocalMode(LLVMValueRef GlobalVar, LLVMThreadLocalMode Mode);
LLVMBool LLVMIsExternallyInitialized(LLVMValueRef GlobalVar);
void LLVMSetExternallyInitialized(LLVMValueRef GlobalVar, LLVMBool IsExtInit);

// Atributos
LLVMAttributeRef LLVMCreateAttribute(LLVMContextRef C, const(char)* K, uint V);
LLVMAttributeRef LLVMGetEnumAttribute(LLVMContextRef C, uint KindID, uint Val);
LLVMAttributeRef LLVMGetStringAttribute(LLVMContextRef C, const(char)* K, uint KLen, const(char)* V, uint VLen);
LLVMBool LLVMIsEnumAttribute(LLVMAttributeRef A);
LLVMBool LLVMIsStringAttribute(LLVMAttributeRef A);
uint LLVMGetEnumAttributeKind(LLVMAttributeRef A);
uint LLVMGetEnumAttributeValue(LLVMAttributeRef A);
const(char)* LLVMGetStringAttributeKind(LLVMAttributeRef A, uint* Length);
const(char)* LLVMGetStringAttributeValue(LLVMAttributeRef A, uint* Length);
void LLVMAddAttributeAtIndex(LLVMValueRef F, uint Idx, LLVMAttributeRef A);
uint LLVMGetAttributeCountAtIndex(LLVMValueRef F, uint Idx);
LLVMAttributeRef LLVMGetAttributeAtIndex(LLVMValueRef F, uint Idx, uint i);
void LLVMRemoveAttributeAtIndex(LLVMValueRef F, uint Idx, LLVMAttributeRef A);
void LLVMAddTargetDependentFunctionAttr(LLVMValueRef Fn, const(char)* A, const(char)* V);

// Execution Engine
LLVMBool LLVMCreateExecutionEngineForModule(LLVMExecutionEngineRef* EE, LLVMModuleRef M, const(char)** OutError);
LLVMBool LLVMCreateInterpreterForModule(LLVMExecutionEngineRef* EE, LLVMModuleRef M, const(char)** OutError);
LLVMBool LLVMCreateJITCompilerForModule(LLVMExecutionEngineRef* EE, LLVMModuleRef M, uint OptLevel, const(
                char)** OutError);
void LLVMDisposeExecutionEngine(LLVMExecutionEngineRef EE);
void LLVMRunStaticConstructors(LLVMExecutionEngineRef EE);
void LLVMRunStaticDestructors(LLVMExecutionEngineRef EE);
ulong LLVMGetFunctionAddress(LLVMExecutionEngineRef EE, const(char)* Name);
LLVMGenericValueRef LLVMRunFunction(LLVMExecutionEngineRef EE, LLVMValueRef F, uint NumArgs, LLVMGenericValueRef* Args);
void LLVMFreeMachineCodeForFunction(LLVMExecutionEngineRef EE, LLVMValueRef F);
void LLVMAddModule(LLVMExecutionEngineRef EE, LLVMModuleRef M);
LLVMBool LLVMRemoveModule(LLVMExecutionEngineRef EE, LLVMModuleRef M, LLVMModuleRef* OutMod, const(
                char)** OutError);
LLVMBool LLVMFindFunction(LLVMExecutionEngineRef EE, const(char)* Name, LLVMValueRef* OutFn);
void* LLVMRecompileAndRelinkFunction(LLVMExecutionEngineRef EE, LLVMValueRef Fn);
LLVMTargetDataRef LLVMGetExecutionEngineTargetData(LLVMExecutionEngineRef EE);
LLVMTargetMachineRef LLVMGetExecutionEngineTargetMachine(LLVMExecutionEngineRef EE);
void LLVMAddGlobalMapping(LLVMExecutionEngineRef EE, LLVMValueRef Global, void* Addr);
void* LLVMGetPointerToGlobal(LLVMExecutionEngineRef EE, LLVMValueRef Global);

// Pass Manager
// LLVMPassManagerRef LLVMCreatePassManager();
// LLVMPassManagerRef LLVMCreateFunctionPassManagerForModule(LLVMModuleRef M);
// LLVMPassManagerRef LLVMCreateFunctionPassManager(LLVMModuleProviderRef MP);
// void LLVMInitializeCore(LLVMPassRegistryRef R);
// void LLVMInitializeTransformUtils(LLVMPassRegistryRef R);
// void LLVMInitializeScalarOpts(LLVMPassRegistryRef R);
// void LLVMInitializeVectorization(LLVMPassRegistryRef R);
// void LLVMInitializeInstCombine(LLVMPassRegistryRef R);
// void LLVMInitializeIPO(LLVMPassRegistryRef R);
// void LLVMInitializeInstrumentation(LLVMPassRegistryRef R);
// void LLVMInitializeAnalysis(LLVMPassRegistryRef R);
// void LLVMInitializeIPA(LLVMPassRegistryRef R);
// void LLVMInitializeCodeGen(LLVMPassRegistryRef R);
// void LLVMInitializeTarget(LLVMPassRegistryRef R);
// void LLVMDisposePassManager(LLVMPassManagerRef PM);
// LLVMBool LLVMRunPassManager(LLVMPassManagerRef PM, LLVMModuleRef M);
// LLVMBool LLVMInitializeFunctionPassManager(LLVMPassManagerRef FPM);
// LLVMBool LLVMRunFunctionPassManager(LLVMPassManagerRef FPM, LLVMValueRef F);
// LLVMBool LLVMFinalizeFunctionPassManager(LLVMPassManagerRef FPM);
// void LLVMAddInstructionCombiningPass(LLVMPassManagerRef PM);
// void LLVMAddConstantPropagationPass(LLVMPassManagerRef PM);
// void LLVMAddDemoteMemoryToRegisterPass(LLVMPassManagerRef PM);
// void LLVMAddGVNPass(LLVMPassManagerRef PM);
// void LLVMAddSCCPPass(LLVMPassManagerRef PM);
// void LLVMAddAggressiveDCEPass(LLVMPassManagerRef PM);
// void LLVMAddCFGSimplificationPass(LLVMPassManagerRef PM);
// void LLVMAddDeadStoreEliminationPass(LLVMPassManagerRef PM);
// void LLVMAddGVNPass(LLVMPassManagerRef PM);
// void LLVMAddIndVarSimplifyPass(LLVMPassManagerRef PM);
// void LLVMAddInstructionCombiningPass(LLVMPassManagerRef PM);
// void LLVMAddJumpThreadingPass(LLVMPassManagerRef PM);
// void LLVMAddLICMPass(LLVMPassManagerRef PM);
// void LLVMAddLoopDeletionPass(LLVMPassManagerRef PM);
// void LLVMAddLoopIdiomPass(LLVMPassManagerRef PM);
// void LLVMAddLoopRotatePass(LLVMPassManagerRef PM);
// void LLVMAddLoopRerollPass(LLVMPassManagerRef PM);
// void LLVMAddLoopUnrollPass(LLVMPassManagerRef PM);
// void LLVMAddLoopUnswitchPass(LLVMPassManagerRef PM);
// void LLVMAddMemCpyOptPass(LLVMPassManagerRef PM);
// void LLVMAddMergedLoadStoreMotionPass(LLVMPassManagerRef PM);
// void LLVMAddPartialInliningPass(LLVMPassManagerRef PM);
// void LLVMAddReassociatePass(LLVMPassManagerRef PM);
// void LLVMAddSCCPPass(LLVMPassManagerRef PM);
// void LLVMAddScalarReplAggregatesPass(LLVMPassManagerRef PM);
// void LLVMAddScalarReplAggregatesPassSSA(LLVMPassManagerRef PM);
// void LLVMAddScalarReplAggregatesPassWithThreshold(LLVMPassManagerRef PM, int Threshold);
// void LLVMAddSimplifyLibCallsPass(LLVMPassManagerRef PM);
// void LLVMAddTailCallEliminationPass(LLVMPassManagerRef PM);
// void LLVMAddConstantPropagationPass(LLVMPassManagerRef PM);
// void LLVMAddDemoteMemoryToRegisterPass(LLVMPassManagerRef PM);
// void LLVMAddVerifierPass(LLVMPassManagerRef PM);
// void LLVMAddCorrelatedValuePropagationPass(LLVMPassManagerRef PM);
// void LLVMAddEarlyCSEPass(LLVMPassManagerRef PM);
// void LLVMAddLowerExpectIntrinsicPass(LLVMPassManagerRef PM);
// void LLVMAddTypeBasedAliasAnalysisPass(LLVMPassManagerRef PM);
// void LLVMAddBasicAliasAnalysisPass(LLVMPassManagerRef PM);

// Target
LLVMBool LLVMInitializeNativeTarget();
LLVMBool LLVMInitializeNativeAsmPrinter();
LLVMBool LLVMInitializeNativeAsmParser();
LLVMTargetRef LLVMGetFirstTarget();
LLVMTargetRef LLVMGetNextTarget(LLVMTargetRef T);
LLVMTargetRef LLVMGetTargetFromName(const(char)* Name);
LLVMBool LLVMGetTargetFromTriple(const(char)* Triple, LLVMTargetRef* T, const(char)** ErrorMessage);
const(char)* LLVMGetTargetName(LLVMTargetRef T);
const(char)* LLVMGetTargetDescription(LLVMTargetRef T);
LLVMTargetMachineRef LLVMCreateTargetMachine(LLVMTargetRef T, const(char)* Triple, const(char)* CPU, const(
                char)* Features, LLVMCodeGenOptLevel Level, LLVMRelocMode Reloc, LLVMCodeModel CodeModel);
void LLVMDisposeTargetMachine(LLVMTargetMachineRef T);
LLVMTargetDataRef LLVMCreateTargetData(const(char)* StringRep);
void LLVMDisposeTargetData(LLVMTargetDataRef TD);
LLVMTargetDataRef LLVMCopyTargetData(LLVMTargetDataRef TD);
void LLVMAddTargetData(LLVMTargetDataRef TD, LLVMPassManagerRef PM);
const(char)* LLVMGetTargetMachineTriple(LLVMTargetMachineRef T);
LLVMTargetRef LLVMGetTargetMachineTarget(LLVMTargetMachineRef T);
const(char)* LLVMGetTargetMachineCPU(LLVMTargetMachineRef T);
const(char)* LLVMGetTargetMachineFeatureString(LLVMTargetMachineRef T);
LLVMTargetDataRef LLVMGetTargetMachineData(LLVMTargetMachineRef T);
LLVMBool LLVMTargetMachineEmitToFile(LLVMTargetMachineRef T, LLVMModuleRef M, const(char)* Filename, LLVMCodeGenFileType codegen, const(
                char)** ErrorMessage);
LLVMBool LLVMTargetMachineEmitToMemoryBuffer(LLVMTargetMachineRef T, LLVMModuleRef M, LLVMCodeGenFileType codegen, const(
                char)** ErrorMessage, LLVMMemoryBufferRef* OutMemBuf);

// Debug Information
LLVMDIBuilderRef LLVMCreateDIBuilder(LLVMModuleRef M);
void LLVMDisposeDIBuilder(LLVMDIBuilderRef Builder);
void LLVMDIBuilderFinalize(LLVMDIBuilderRef Builder);
LLVMMetadataRef LLVMDIBuilderCreateCompileUnit(LLVMDIBuilderRef Builder, LLVMDWARFSourceLanguage Lang, LLVMMetadataRef FileRef, const(
                char)* Producer, uint ProducerLen, LLVMBool isOptimized, const(char)* Flags, uint FlagsLen, uint RuntimeVer, const(
                char)* SplitName, uint SplitNameLen, LLVMDWARFEmissionKind Kind, uint DWOId, LLVMBool SplitDebugInlining, LLVMBool DebugInfoForProfiling);
LLVMMetadataRef LLVMDIBuilderCreateFile(LLVMDIBuilderRef Builder, const(char)* Filename, uint FilenameLen, const(
                char)* Directory, uint DirectoryLen);
LLVMMetadataRef LLVMDIBuilderCreateSubroutineType(LLVMDIBuilderRef Builder, LLVMMetadataRef File, LLVMMetadataRef* ParameterTypes, uint NumParameterTypes, LLVMDIFlags Flags);
LLVMMetadataRef LLVMDIBuilderCreateFunction(LLVMDIBuilderRef Builder, LLVMMetadataRef Scope, const(char)* Name, uint NameLen, const(
                char)* LinkageName, uint LinkageNameLen, LLVMMetadataRef File, uint LineNo, LLVMMetadataRef Ty, LLVMBool IsLocalToUnit, LLVMBool IsDefinition, uint ScopeLine, LLVMDIFlags Flags, LLVMBool IsOptimized);
LLVMMetadataRef LLVMDIBuilderCreateBasicType(LLVMDIBuilderRef Builder, const(char)* Name, uint NameLen, uint SizeInBits, uint Encoding, LLVMDIFlags Flags);
LLVMMetadataRef LLVMDIBuilderCreatePointerType(LLVMDIBuilderRef Builder, LLVMMetadataRef PointeeTy, uint SizeInBits, uint AlignInBits, LLVMDWARFAddressSpace AddressSpace, const(
                char)* Name, uint NameLen);
LLVMMetadataRef LLVMDIBuilderCreateStructType(LLVMDIBuilderRef Builder, LLVMMetadataRef Scope, const(char)* Name, uint NameLen, LLVMMetadataRef File, uint LineNumber, uint SizeInBits, uint AlignInBits, LLVMDIFlags Flags, LLVMMetadataRef DerivedFrom, LLVMMetadataRef* Elements, uint NumElements, uint RunTimeLang, LLVMMetadataRef VTableHolder, const(
                char)* UniqueId, uint UniqueIdLen);
LLVMMetadataRef LLVMDIBuilderCreateMemberType(LLVMDIBuilderRef Builder, LLVMMetadataRef Scope, const(char)* Name, uint NameLen, LLVMMetadataRef File, uint LineNumber, uint SizeInBits, uint AlignInBits, uint OffsetInBits, LLVMDIFlags Flags, LLVMMetadataRef Ty);
LLVMMetadataRef LLVMDIBuilderCreateArrayType(LLVMDIBuilderRef Builder, uint Size, uint AlignInBits, LLVMMetadataRef Ty, LLVMMetadataRef* Subscripts, uint NumSubscripts);
LLVMMetadataRef LLVMDIBuilderGetOrCreateSubarray(LLVMDIBuilderRef Builder, LLVMMetadataRef* Subscripts, uint NumSubscripts);
LLVMMetadataRef LLVMDIBuilderCreateExpression(LLVMDIBuilderRef Builder, int64_t* Addr, uint Length);
LLVMMetadataRef LLVMDIBuilderCreateConstantValueExpression(LLVMDIBuilderRef Builder, int64_t Value);
LLVMMetadataRef LLVMDIBuilderCreateGlobalVariableExpression(
        LLVMDIBuilderRef Builder, LLVMMetadataRef Scope, const(char)* Name, uint NameLen, const(char)* Linkage, uint LinkageLen, LLVMMetadataRef File, uint LineNo, LLVMMetadataRef Ty, LLVMBool IsLocalToUnit, LLVMMetadataRef Expr, LLVMMetadataRef Decl, uint AlignInBits);
LLVMMetadataRef LLVMDIBuilderCreateAutoVariable(LLVMDIBuilderRef Builder, LLVMMetadataRef Scope, const(char)* Name, uint NameLen, LLVMMetadataRef File, uint LineNo, LLVMMetadataRef Ty, LLVMBool AlwaysPreserve, LLVMDIFlags Flags, uint AlignInBits);
LLVMMetadataRef LLVMDIBuilderCreateParameterVariable(LLVMDIBuilderRef Builder, LLVMMetadataRef Scope, const(char)* Name, uint NameLen, uint ArgNo, LLVMMetadataRef File, uint LineNo, LLVMMetadataRef Ty, LLVMBool AlwaysPreserve, LLVMDIFlags Flags);
LLVMMetadataRef LLVMDIBuilderCreateLexicalBlock(LLVMDIBuilderRef Builder, LLVMMetadataRef Scope, LLVMMetadataRef File, uint Line, uint Column);
LLVMMetadataRef LLVMDIBuilderCreateLexicalBlockFile(LLVMDIBuilderRef Builder, LLVMMetadataRef Scope, LLVMMetadataRef File, uint Discriminator);
LLVMMetadataRef LLVMDIBuilderInsertDeclareAtEnd(LLVMDIBuilderRef Builder, LLVMValueRef Storage, LLVMMetadataRef VarInfo, LLVMMetadataRef Expr, LLVMMetadataRef DebugLoc, LLVMBasicBlockRef Block);
LLVMMetadataRef LLVMDIBuilderInsertDbgValueAtEnd(LLVMDIBuilderRef Builder, LLVMValueRef Val, LLVMMetadataRef VarInfo, LLVMMetadataRef Expr, LLVMMetadataRef DebugLoc, LLVMBasicBlockRef Block);

// Utilitários
void LLVMDumpValue(LLVMValueRef Val);
void LLVMDumpModule(LLVMModuleRef M);
LLVMBool LLVMPrintModuleToFile(LLVMModuleRef M, const(char)* Filename, const(char)** ErrorMessage);
LLVMBool LLVMPrintValueToFile(LLVMValueRef Val, const(char)* Filename, const(char)** ErrorMessage);
char* LLVMPrintValueToString(LLVMValueRef Val);
char* LLVMPrintTypeToString(LLVMTypeRef Ty);
void LLVMSetCurrentDebugLocation(LLVMBuilderRef Builder, LLVMMetadataRef Loc);
LLVMMetadataRef LLVMGetCurrentDebugLocation(LLVMBuilderRef Builder);
void LLVMSetInstDebugLocation(LLVMBuilderRef Builder, LLVMValueRef Inst);
LLVMValueRef LLVMRunPasses(LLVMModuleRef M, const(char)* Passes, LLVMTargetMachineRef TM, void* Options);
void LLVMStructSetBody(LLVMTypeRef StructTy, LLVMTypeRef* ElementTypes, uint ElementCount, LLVMBool Packed);
LLVMTypeRef LLVMGetReturnType(LLVMTypeRef FunctionTy);
LLVMTypeKind LLVMGetTypeKind(LLVMTypeRef Ty);
LLVMTypeRef LLVMGetElementType(LLVMTypeRef Ty);
LLVMTypeRef LLVMGlobalGetValueType(LLVMValueRef Global);
uint LLVMCountParams(LLVMValueRef Fn);
ulong LLVMSizeOfTypeInBits(LLVMTargetDataRef TD, LLVMTypeRef Ty);
const(char)* LLVMGetDefaultTargetTriple();
LLVMTargetDataRef LLVMCreateTargetDataLayout(LLVMTargetMachineRef T);
const(char)* LLVMCopyStringRepOfTargetData(LLVMTargetDataRef TD);
void LLVMDisposeMessage(char* Message);

// TARGETS //

// X86
void LLVMInitializeX86Target();
void LLVMInitializeX86TargetInfo();
void LLVMInitializeX86TargetMC();
void LLVMInitializeX86AsmPrinter();
void LLVMInitializeX86AsmParser();

// AArch64
void LLVMInitializeAArch64Target();
void LLVMInitializeAArch64TargetInfo();
void LLVMInitializeAArch64TargetMC();
void LLVMInitializeAArch64AsmPrinter();
void LLVMInitializeAArch64AsmParser();

// ARM
void LLVMInitializeARMTarget();
void LLVMInitializeARMTargetInfo();
void LLVMInitializeARMTargetMC();
void LLVMInitializeARMAsmPrinter();
void LLVMInitializeARMAsmParser();

uint LLVMCountParamTypes(LLVMTypeRef FunctionType);
void LLVMGetParamTypes(LLVMTypeRef FunctionType, LLVMTypeRef* ParamTypes);

uint LLVMGetIntTypeWidth(LLVMTypeRef IntegerTy);

void LLVMAddIncoming(
        LLVMValueRef PhiNode,
        LLVMValueRef* IncomingValues,
        LLVMBasicBlockRef* IncomingBlocks,
        uint Count
);

LLVMOpcode LLVMGetInstructionOpcode(LLVMValueRef Inst);
LLVMValueRef LLVMGetLastInstruction(LLVMBasicBlockRef BasicBlock);
char* LLVMPrintModuleToString(LLVMModuleRef M);
