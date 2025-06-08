'use client';

import React, { useState, useEffect } from 'react';
import { ConnectButton } from '@rainbow-me/rainbowkit';
import { useAccount, useSignMessage } from 'wagmi';
import { AuthKitProvider, SignInButton, useProfile } from '@farcaster/auth-kit';
import MatrixClient from '../components/MatrixClient';

export default function Home() {
  const { address, isConnected } = useAccount();
  const { signMessageAsync } = useSignMessage();
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [authMethod, setAuthMethod] = useState<'wallet' | 'farcaster' | null>(null);
  const [matrixCredentials, setMatrixCredentials] = useState(null);
  const [loading, setLoading] = useState(false);

  // Farcaster profile
  const {
    isAuthenticated: isFarcasterAuthenticated,
    profile: farcasterProfile,
  } = useProfile();

  const handleWalletAuth = async () => {
    if (!address || !isConnected) return;

    setLoading(true);
    try {
      const message = `Authenticate to Chatimics Matrix Server\nWallet: ${address}\nTimestamp: ${Date.now()}`;
      const signature = await signMessageAsync({ message });

      const response = await fetch('/api/authenticate', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          address,
          signature,
          message,
          authMethod: 'wallet'
        })
      });

      const data = await response.json();
      if (data.success) {
        setMatrixCredentials(data);
        setAuthMethod('wallet');
        setIsAuthenticated(true);
      } else {
        throw new Error(data.error);
      }
    } catch (error) {
      console.error('Wallet authentication failed:', error);
      alert('Authentication failed: ' + error.message);
    } finally {
      setLoading(false);
    }
  };

  const handleFarcasterAuth = async () => {
    if (!isFarcasterAuthenticated || !farcasterProfile) return;

    setLoading(true);
    try {
      const response = await fetch('/api/authenticate', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          farcasterProfile,
          authMethod: 'farcaster'
        })
      });

      const data = await response.json();
      if (data.success) {
        setMatrixCredentials(data);
        setAuthMethod('farcaster');
        setIsAuthenticated(true);
      } else {
        throw new Error(data.error);
      }
    } catch (error) {
      console.error('Farcaster authentication failed:', error);
      alert('Authentication failed: ' + error.message);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (isFarcasterAuthenticated && farcasterProfile && !isAuthenticated) {
      handleFarcasterAuth();
    }
  }, [isFarcasterAuthenticated, farcasterProfile]);

  if (isAuthenticated && matrixCredentials) {
    return (
      <MatrixClient 
        credentials={matrixCredentials}
        authMethod={authMethod}
        onLogout={() => {
          setIsAuthenticated(false);
          setMatrixCredentials(null);
          setAuthMethod(null);
        }}
      />
    );
  }

  return (
    <div className="gradient-bg min-h-screen">
      <div className="container mx-auto px-4 py-8">
        {/* Header */}
        <header className="text-center mb-12">
          <h1 className="text-5xl font-bold text-white mb-4 animate-fade-in">
            <i className="fas fa-comments mr-3"></i>Chatimics
          </h1>
          <p className="text-xl text-gray-200">
            Secure Matrix Chat with Crypto & Farcaster Authentication
          </p>
        </header>

        {/* Auth Options */}
        <div className="max-w-4xl mx-auto">
          <div className="glass-effect rounded-2xl p-8 animate-slide-up">
            <div className="text-center mb-8">
              <h2 className="text-3xl font-bold text-white mb-4">
                Choose Your Authentication Method
              </h2>
              <p className="text-gray-200">
                Connect with your crypto wallet or Farcaster account
              </p>
            </div>

            <div className="grid md:grid-cols-2 gap-8">
              {/* Wallet Authentication */}
              <div className="glass-effect rounded-xl p-6 text-center">
                <div className="mb-6">
                  <i className="fas fa-wallet text-6xl text-blue-400 mb-4"></i>
                  <h3 className="text-2xl font-semibold text-white mb-2">
                    Crypto Wallet
                  </h3>
                  <p className="text-gray-300 mb-6">
                    Connect with MetaMask, WalletConnect, Coinbase, and 100+ other wallets
                  </p>
                </div>

                <div className="space-y-4">
                  <ConnectButton />
                  
                  {isConnected && (
                    <button
                      onClick={handleWalletAuth}
                      disabled={loading}
                      className="w-full bg-blue-600 hover:bg-blue-700 disabled:bg-blue-400 text-white font-bold py-3 px-6 rounded-lg transition-colors duration-200"
                    >
                      {loading ? (
                        <i className="fas fa-spinner fa-spin mr-2"></i>
                      ) : (
                        <i className="fas fa-signature mr-2"></i>
                      )}
                      Sign & Authenticate
                    </button>
                  )}
                </div>
              </div>

              {/* Farcaster Authentication */}
              <div className="glass-effect rounded-xl p-6 text-center">
                <div className="mb-6">
                  <div className="text-6xl text-farcaster mb-4">🟣</div>
                  <h3 className="text-2xl font-semibold text-white mb-2">
                    Farcaster
                  </h3>
                  <p className="text-gray-300 mb-6">
                    Sign in with your Farcaster account for seamless social authentication
                  </p>
                </div>

                <div className="space-y-4">
                  {!isFarcasterAuthenticated ? (
                    <SignInButton />
                  ) : (
                    <div className="space-y-4">
                      <div className="bg-green-500 bg-opacity-20 border border-green-500 rounded-lg p-4">
                        <div className="flex items-center justify-center">
                          <i className="fas fa-check-circle text-green-400 mr-3"></i>
                          <div>
                            <p className="text-white font-semibold">
                              Connected as @{farcasterProfile?.username}
                            </p>
                            <p className="text-gray-300 text-sm">
                              FID: {farcasterProfile?.fid}
                            </p>
                          </div>
                        </div>
                      </div>
                      
                      {!isAuthenticated && (
                        <button
                          onClick={handleFarcasterAuth}
                          disabled={loading}
                          className="w-full bg-farcaster hover:bg-farcaster-light disabled:bg-farcaster-light text-white font-bold py-3 px-6 rounded-lg transition-colors duration-200"
                        >
                          {loading ? (
                            <i className="fas fa-spinner fa-spin mr-2"></i>
                          ) : (
                            <i className="fas fa-sign-in-alt mr-2"></i>
                          )}
                          Enter Chat
                        </button>
                      )}
                    </div>
                  )}
                </div>
              </div>
            </div>

            {/* Features */}
            <div className="mt-12 grid md:grid-cols-3 gap-6">
              <div className="text-center">
                <i className="fas fa-shield-alt text-3xl text-green-400 mb-3"></i>
                <h4 className="text-lg font-semibold text-white mb-2">Secure</h4>
                <p className="text-gray-300 text-sm">
                  Cryptographic authentication ensures only approved users can access
                </p>
              </div>
              <div className="text-center">
                <i className="fas fa-users text-3xl text-blue-400 mb-3"></i>
                <h4 className="text-lg font-semibold text-white mb-2">Social</h4>
                <p className="text-gray-300 text-sm">
                  Connect with Farcaster to bring your social identity
                </p>
              </div>
              <div className="text-center">
                <i className="fas fa-bolt text-3xl text-yellow-400 mb-3"></i>
                <h4 className="text-lg font-semibold text-white mb-2">Fast</h4>
                <p className="text-gray-300 text-sm">
                  Real-time messaging powered by Matrix protocol
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Add Font Awesome */}
      <link 
        href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" 
        rel="stylesheet" 
      />
    </div>
  );
}
