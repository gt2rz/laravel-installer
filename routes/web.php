<?php

use Illuminate\Support\Facades\Route;

Route::get('/', function () {
    return view('welcome');
});

Route::get('/ping', fn () => response()->json(['status' => 'ok', 'server' => 'frankenphp']));
