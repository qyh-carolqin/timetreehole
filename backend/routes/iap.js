const express = require('express');
const {
    db,
    RECHARGE_PACKAGES,
    findPackageByAppleProductId,
    findAppleProductId,
    addCredits,
    insertIAPTransaction,
    findTransactionByAppleId,
} = require('../db');

const router = express.Router();

// ============================================================
// Apple App Store 收据验证配置
// ============================================================

const APP_BUNDLE_ID = 'com.carolqin.timetreehole';
const APPLE_SHARED_SECRET = process.env.APPLE_SHARED_SECRET || '';

const APPLE_VERIFY_URLS = {
    production: 'https://buy.itunes.apple.com/verifyReceipt',
    sandbox:    'https://sandbox.itunes.apple.com/verifyReceipt',
};

// ============================================================
// POST /api/iap/verify — 验证 Apple 收据并发放灵叶
// ============================================================

router.post('/verify', async (req, res) => {
    try {
        const { receiptData, packageId, transactionId, productId } = req.body;

        // --- 参数校验 ---

        if (!receiptData || !packageId || !transactionId || !productId) {
            return res.status(400).json({
                success: false,
                error: 'missing_params',
                message: '缺少必要参数 (receiptData / packageId / transactionId / productId)',
            });
        }

        // --- 防重放：检查 transaction_id 是否已处理 ---

        const existing = findTransactionByAppleId.get(transactionId);
        if (existing) {
            console.warn(`🔁 [IAP] 重复交易请求: transaction_id=${transactionId}`);
            return res.status(409).json({
                success: false,
                error: 'duplicate_transaction',
                message: '该交易已处理过',
            });
        }

        // --- 套餐校验 ---

        const pkg = RECHARGE_PACKAGES.find(p => p.id === packageId);
        if (!pkg) {
            return res.status(400).json({
                success: false,
                error: 'invalid_package',
                message: '无效的充值套餐',
            });
        }

        if (pkg.appleProductId !== productId) {
            console.error(`❌ [IAP] 套餐产品 ID 不匹配: package="${packageId}" apple_product="${pkg.appleProductId}" received="${productId}"`);
            return res.status(400).json({
                success: false,
                error: 'product_mismatch',
                message: '产品 ID 与套餐不匹配',
            });
        }

        // --- 调用 Apple 验证收据 ---

        const verifyResult = await verifyReceiptWithApple(receiptData, transactionId);

        if (!verifyResult.valid) {
            console.error(`❌ [IAP] Apple 收据验证失败: ${verifyResult.error}`);
            return res.status(400).json({
                success: false,
                error: 'receipt_invalid',
                message: verifyResult.error || '收据验证失败',
            });
        }

        // --- 验证返回的产品信息 ---

        const appleReceipt = verifyResult.receipt;
        const bundleIdOk = appleReceipt.bundle_id === APP_BUNDLE_ID;
        const productIdOk = appleReceipt.product_id === productId;

        if (!bundleIdOk) {
            console.error(`❌ [IAP] Bundle ID 不匹配: expected="${APP_BUNDLE_ID}" got="${appleReceipt.bundle_id}"`);
            return res.status(400).json({
                success: false,
                error: 'bundle_mismatch',
                message: 'Bundle ID 验证失败',
            });
        }

        if (!productIdOk) {
            console.error(`❌ [IAP] 收据产品 ID 不匹配: expected="${productId}" got="${appleReceipt.product_id}"`);
            return res.status(400).json({
                success: false,
                error: 'product_mismatch',
                message: '产品 ID 验证失败',
            });
        }

        const environment = verifyResult.environment;
        const originalTransactionId = appleReceipt.original_transaction_id || transactionId;

        // --- 发放灵叶 + 记录交易（事务保护） ---

        const grantResult = db.transaction(() => {
            // 再次防重检查（并发保护）
            const dup = findTransactionByAppleId.get(transactionId);
            if (dup) {
                return { skipped: true };
            }

            // 加灵叶
            addCredits.run(pkg.credits, req.user.id);

            // 记录 Apple IAP 交易
            insertIAPTransaction.run(
                req.user.id,
                pkg.credits,
                `iap_${packageId}`,
                transactionId,
                originalTransactionId,
                null,           // receipt_data 太长不存，只存必要字段
                productId,
                environment
            );

            // 获取最新余额
            const updated = db.prepare('SELECT credits FROM users WHERE id = ?').get(req.user.id);

            return {
                skipped: false,
                credits: updated.credits,
            };
        })();

        if (grantResult.skipped) {
            console.warn(`🔁 [IAP] 事务内检测到重复交易: transaction_id=${transactionId}`);
            return res.status(409).json({
                success: false,
                error: 'duplicate_transaction',
                message: '该交易已处理过',
            });
        }

        const totalCredits = grantResult.credits;

        console.log(`💰 [IAP] 充值成功 user_id=${req.user.id} product=${productId} +${pkg.credits}灵叶 → 余额=${totalCredits} env=${environment}`);

        res.json({
            success: true,
            addedCredits: pkg.credits,
            totalCredits: totalCredits,
            transactionId: transactionId,
            package: pkg.name,
        });

    } catch (err) {
        console.error('[IAP] 验证异常:', err);
        res.status(500).json({
            success: false,
            error: 'verify_failed',
            message: '验证服务异常，请稍后重试',
        });
    }
});

// ============================================================
// 收据验证核心函数
// ============================================================

/**
 * 向 Apple 验证收据
 * @returns {{ valid: boolean, receipt?: object, environment?: string, error?: string }}
 */
async function verifyReceiptWithApple(receiptData, transactionId) {
    // 先尝试生产环境
    const prodResult = await callAppleVerify(APPLE_VERIFY_URLS.production, receiptData);
    const status = prodResult.status;

    // status 0 = 验证通过
    if (status === 0) {
        const inAppReceipt = findInAppReceipt(prodResult, transactionId);
        if (!inAppReceipt) {
            return { valid: false, error: '收据中未找到对应交易' };
        }
        return {
            valid: true,
            receipt: inAppReceipt,
            environment: 'Production',
        };
    }

    // status 21007 = 沙盒收据发到了生产环境，重试沙盒
    if (status === 21007) {
        console.log('🔄 [IAP] 检测到沙盒收据，切换到沙盒环境验证');
        const sandResult = await callAppleVerify(APPLE_VERIFY_URLS.sandbox, receiptData);

        if (sandResult.status === 0) {
            const inAppReceipt = findInAppReceipt(sandResult, transactionId);
            if (!inAppReceipt) {
                return { valid: false, error: '收据中未找到对应交易' };
            }
            return {
                valid: true,
                receipt: inAppReceipt,
                environment: 'Sandbox',
            };
        }

        return {
            valid: false,
            error: `沙盒验证失败 (status: ${sandResult.status})`,
        };
    }

    // 其他错误码
    const errorMessages = {
        21000: 'App Store 无法读取收据数据',
        21002: '收据数据格式错误',
        21003: '收据认证失败',
        21004: '共享密钥不匹配',
        21005: '收据服务器不可用',
        21006: '收据有效但订阅已过期',
        21008: '收据发给了生产环境但来自沙盒',
        21010: '收据被吊销',
    };

    const errorMsg = errorMessages[status] || `Apple 验证返回 status: ${status}`;
    return { valid: false, error: errorMsg };
}

/**
 * 调用 Apple verifyReceipt API
 */
async function callAppleVerify(url, receiptData) {
    const body = JSON.stringify({
        'receipt-data': receiptData,
        'password': APPLE_SHARED_SECRET,
        'exclude-old-transactions': true,
    });

    const response = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: body,
    });

    if (!response.ok) {
        throw new Error(`Apple API 请求失败: HTTP ${response.status}`);
    }

    return await response.json();
}

/**
 * 从 Apple 返回的收据中查找匹配的 in-app purchase
 */
function findInAppReceipt(appleResponse, transactionId) {
    // App Store Server API v1 (verifyReceipt) 格式
    const receipt = appleResponse.receipt;
    if (!receipt) return null;

    const inAppPurchases = receipt.in_app || [];

    // 按 transaction_id 精确匹配
    const match = inAppPurchases.find(
        entry => entry.transaction_id === transactionId
    );

    if (match) return match;

    // 如果精确匹配不到，取最后一条（可能原始 transaction_id 不同）
    if (inAppPurchases.length > 0) {
        return inAppPurchases[inAppPurchases.length - 1];
    }

    return null;
}

module.exports = router;
