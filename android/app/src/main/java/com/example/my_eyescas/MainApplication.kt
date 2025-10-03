package com.example.my_eyescas

import android.app.Application
import androidx.work.Configuration
import androidx.work.WorkManager

class MainApplication : Application(), Configuration.Provider {
    override fun onCreate() {
        super.onCreate()
        // WorkManager se inicializará automáticamente a través de Configuration.Provider
    }

    override fun getWorkManagerConfiguration(): Configuration {
        return Configuration.Builder()
            .setMinimumLoggingLevel(android.util.Log.INFO)
            .build()
    }
}