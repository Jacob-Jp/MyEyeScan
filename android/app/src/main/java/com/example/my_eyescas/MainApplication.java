package com.example.my_eyescas;

import android.app.Application;
import androidx.work.Configuration;
import androidx.work.WorkManager;
import android.util.Log;

public class MainApplication extends Application implements Configuration.Provider {
    
    @Override
    public void onCreate() {
        super.onCreate();
        // WorkManager se inicializará automáticamente a través de Configuration.Provider
    }

    @Override
    public Configuration getWorkManagerConfiguration() {
        return new Configuration.Builder()
                .setMinimumLoggingLevel(Log.INFO)
                .build();
    }
}
