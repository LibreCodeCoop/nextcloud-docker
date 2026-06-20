<?php

$bucket = getenv('GARAGES3_BUCKET') ?: 'nextcloud';
$key = getenv('GARAGES3_KEY');
$secret = getenv('GARAGES3_SECRET');

if ($key === false || $key === '' || $secret === false || $secret === '') {
    throw new RuntimeException('GARAGES3_KEY and GARAGES3_SECRET must be set for Garage S3 primary storage.');
}

$CONFIG = [
    'objectstore' => [
        'class' => '\\OC\\Files\\ObjectStore\\S3',
        'arguments' => [
            'bucket' => $bucket,
            'hostname' => getenv('GARAGES3_HOSTNAME') ?: 'host.docker.internal',
            'port' => (int) (getenv('GARAGES3_PORT') ?: 3900),
            'region' => getenv('GARAGES3_REGION') ?: 'garage',
            'key' => $key,
            'secret' => $secret,
            'use_ssl' => filter_var(getenv('GARAGES3_USE_SSL') ?: 'false', FILTER_VALIDATE_BOOLEAN),
            'use_path_style' => filter_var(getenv('GARAGES3_USE_PATH_STYLE') ?: 'true', FILTER_VALIDATE_BOOLEAN),
            'autocreate' => filter_var(getenv('GARAGES3_AUTOCREATE') ?: 'true', FILTER_VALIDATE_BOOLEAN),
            'verify_bucket_exists' => filter_var(getenv('GARAGES3_VERIFY_BUCKET_EXISTS') ?: 'true', FILTER_VALIDATE_BOOLEAN),
        ],
    ],
];
