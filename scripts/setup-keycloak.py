#!/usr/bin/env python3
"""
Keycloak Setup Script for LlamaStack Auth Demo

This script automatically configures Keycloak with the necessary realm, client, roles, and users
for the LlamaStack authentication demo.

Usage:
    python setup-keycloak.py

Environment Variables:
    KEYCLOAK_URL: Keycloak base URL (default: https://kc-keycloak.com)
    KEYCLOAK_ADMIN_PASSWORD: Admin password (default: dummy)
"""

import os
import sys
import json
import requests
import urllib3
from typing import Dict, Any, Optional

# Disable SSL warnings for demo purposes
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

class KeycloakSetup:
    def __init__(self, base_url: str, admin_password: str):
        self.base_url = base_url.rstrip('/')
        self.admin_password = admin_password
        self.admin_token = None
        self.realm_name = "llamastack-demo"
        self.client_id = "llamastack"

    def get_admin_token(self) -> str:
        """Get admin access token"""
        url = f"{self.base_url}/realms/master/protocol/openid-connect/token"
        data = {
            'client_id': 'admin-cli',
            'username': 'admin',
            'password': self.admin_password,
            'grant_type': 'password'
        }

        response = requests.post(url, data=data, verify=False)
        if response.status_code != 200:
            raise Exception(f"Failed to get admin token: {response.text}")

        return response.json()['access_token']

    def create_realm(self) -> bool:
        """Create the llamastack-demo realm"""
        if not self.admin_token:
            self.admin_token = self.get_admin_token()

        headers = {
            'Authorization': f'Bearer {self.admin_token}',
            'Content-Type': 'application/json'
        }

        realm_config = {
            "realm": self.realm_name,
            "enabled": True,
            "displayName": "LlamaStack Demo Realm",
            "accessTokenLifespan": 43200,
            "ssoSessionMaxLifespan": 43200,
            "registrationAllowed": False,
            "loginWithEmailAllowed": True,
            "duplicateEmailsAllowed": False
        }

        url = f"{self.base_url}/admin/realms"
        response = requests.post(url, headers=headers, json=realm_config, verify=False)

        if response.status_code == 201:
            print(f"✓ Created realm: {self.realm_name}")
            return True
        elif response.status_code == 409:
            print(f"✓ Realm {self.realm_name} already exists")
            return True
        else:
            print(f"✗ Failed to create realm: {response.text}")
            return False

    def create_client(self) -> bool:
        """Create the llamastack client"""
        headers = {
            'Authorization': f'Bearer {self.admin_token}',
            'Content-Type': 'application/json'
        }

        client_config = {
            "clientId": self.client_id,
            "enabled": True,
            "publicClient": False,
            "directAccessGrantsEnabled": True,
            "serviceAccountsEnabled": True,
            "standardFlowEnabled": True,
            "implicitFlowEnabled": False,
            "redirectUris": ["*"],
            "webOrigins": ["*"],
            "protocol": "openid-connect",
            "attributes": {
                "access.token.lifespan": "43200"
            }
        }

        url = f"{self.base_url}/admin/realms/{self.realm_name}/clients"
        response = requests.post(url, headers=headers, json=client_config, verify=False)

        if response.status_code == 201:
            print(f"✓ Created client: {self.client_id}")
            return True
        elif response.status_code == 409:
            print(f"✓ Client {self.client_id} already exists")
            return True
        else:
            print(f"✗ Failed to create client: {response.text}")
            return False

    def get_client_uuid(self) -> Optional[str]:
        """Get the UUID of the llamastack client"""
        headers = {
            'Authorization': f'Bearer {self.admin_token}',
            'Content-Type': 'application/json'
        }

        url = f"{self.base_url}/admin/realms/{self.realm_name}/clients"
        response = requests.get(url, headers=headers, verify=False)

        if response.status_code == 200:
            clients = response.json()
            for client in clients:
                if client['clientId'] == self.client_id:
                    return client['id']
        return None

    def get_client_secret(self) -> Optional[str]:
        """Get the client secret"""
        client_uuid = self.get_client_uuid()
        if not client_uuid:
            return None

        headers = {
            'Authorization': f'Bearer {self.admin_token}',
            'Content-Type': 'application/json'
        }

        url = f"{self.base_url}/admin/realms/{self.realm_name}/clients/{client_uuid}/client-secret"
        response = requests.get(url, headers=headers, verify=False)

        if response.status_code == 200:
            return response.json()['value']
        return None

    def create_roles(self) -> bool:
        """Create the required roles"""
        headers = {
            'Authorization': f'Bearer {self.admin_token}',
            'Content-Type': 'application/json'
        }

        roles = [
            {"name": "admin", "description": "Full access to all resources and operations"},
            {"name": "developer", "description": "Read most models, manage vector stores and files"},
            {"name": "user", "description": "Read-only access to free/shared models"}
        ]

        success = True
        for role in roles:
            url = f"{self.base_url}/admin/realms/{self.realm_name}/roles"
            response = requests.post(url, headers=headers, json=role, verify=False)

            if response.status_code == 201:
                print(f"✓ Created role: {role['name']}")
            elif response.status_code == 409:
                print(f"✓ Role {role['name']} already exists")
            else:
                print(f"✗ Failed to create role {role['name']}: {response.text}")
                success = False

        return success

    def create_protocol_mappers(self) -> bool:
        """Create custom protocol mappers for LlamaStack roles and teams"""
        client_uuid = self.get_client_uuid()
        if not client_uuid:
            print("✗ Cannot create protocol mappers: client not found")
            return False

        headers = {
            'Authorization': f'Bearer {self.admin_token}',
            'Content-Type': 'application/json'
        }

        # Roles mapper
        roles_mapper_config = {
            "name": "llamastack-roles",
            "protocol": "openid-connect",
            "protocolMapper": "oidc-usermodel-realm-role-mapper",
            "consentRequired": False,
            "config": {
                "multivalued": "true",
                "userinfo.token.claim": "true",
                "id.token.claim": "true",
                "access.token.claim": "true",
                "claim.name": "llamastack_roles",
                "jsonType.label": "String",
                "full.path": "false"
            }
        }

        # Teams mapper (using groups)
        teams_mapper_config = {
            "name": "llamastack-teams",
            "protocol": "openid-connect",
            "protocolMapper": "oidc-group-membership-mapper",
            "consentRequired": False,
            "config": {
                "full.path": "false",
                "id.token.claim": "true",
                "access.token.claim": "true",
                "claim.name": "llamastack_teams",
                "userinfo.token.claim": "true"
            }
        }

        url = f"{self.base_url}/admin/realms/{self.realm_name}/clients/{client_uuid}/protocol-mappers/models"

        success = True
        for mapper_config in [roles_mapper_config, teams_mapper_config]:
            response = requests.post(url, headers=headers, json=mapper_config, verify=False)

            if response.status_code == 201:
                print(f"✓ Created protocol mapper: {mapper_config['name']}")
            elif response.status_code == 409:
                print(f"✓ Protocol mapper {mapper_config['name']} already exists")
            else:
                print(f"✗ Failed to create protocol mapper {mapper_config['name']}: {response.text}")
                success = False

        return success

    def create_groups(self) -> bool:
        """Create groups (teams) for the demo"""
        headers = {
            'Authorization': f'Bearer {self.admin_token}',
            'Content-Type': 'application/json'
        }

        groups = [
            {"name": "platform-team", "path": "/platform-team"},
            {"name": "ml-team", "path": "/ml-team"},
            {"name": "data-team", "path": "/data-team"},
        ]

        success = True
        for group in groups:
            url = f"{self.base_url}/admin/realms/{self.realm_name}/groups"
            response = requests.post(url, headers=headers, json=group, verify=False)

            if response.status_code == 201:
                print(f"✓ Created group: {group['name']}")
            elif response.status_code == 409:
                print(f"✓ Group {group['name']} already exists")
            else:
                print(f"✗ Failed to create group {group['name']}: {response.text}")
                success = False

        return success

    def get_group_id(self, group_name: str) -> Optional[str]:
        """Get group ID by name"""
        headers = {
            'Authorization': f'Bearer {self.admin_token}',
            'Content-Type': 'application/json'
        }

        url = f"{self.base_url}/admin/realms/{self.realm_name}/groups"
        response = requests.get(url, headers=headers, verify=False)

        if response.status_code == 200:
            groups = response.json()
            for group in groups:
                if group['name'] == group_name:
                    return group['id']
        return None

    def assign_user_to_group(self, user_id: str, group_id: str) -> bool:
        """Assign user to a group"""
        headers = {
            'Authorization': f'Bearer {self.admin_token}',
            'Content-Type': 'application/json'
        }

        url = f"{self.base_url}/admin/realms/{self.realm_name}/users/{user_id}/groups/{group_id}"
        response = requests.put(url, headers=headers, verify=False)

        return response.status_code == 204

    def create_users(self) -> bool:
        """Create demo users with appropriate roles and teams"""
        headers = {
            'Authorization': f'Bearer {self.admin_token}',
            'Content-Type': 'application/json'
        }

        users = [
            {
                "username": "admin",
                "email": "admin@example.com",
                "firstName": "Admin",
                "lastName": "User",
                "enabled": True,
                "emailVerified": True,
                "credentials": [{"type": "password", "value": "admin123", "temporary": False}],
                "roles": ["admin"],
                "teams": ["platform-team"]
            },
            {
                "username": "developer",
                "email": "developer@example.com",
                "firstName": "Developer",
                "lastName": "User",
                "enabled": True,
                "emailVerified": True,
                "credentials": [{"type": "password", "value": "dev123", "temporary": False}],
                "roles": ["developer"],
                "teams": ["ml-team"]
            },
            {
                "username": "developer2",
                "email": "developer2@example.com",
                "firstName": "Developer Two",
                "lastName": "User",
                "enabled": True,
                "emailVerified": True,
                "credentials": [{"type": "password", "value": "dev123", "temporary": False}],
                "roles": ["developer"],
                "teams": ["ml-team"]
            },
            {
                "username": "developer3",
                "email": "developer3@example.com",
                "firstName": "Developer Three",
                "lastName": "User",
                "enabled": True,
                "emailVerified": True,
                "credentials": [{"type": "password", "value": "dev123", "temporary": False}],
                "roles": ["developer"],
                "teams": ["data-team"]
            },
            {
                "username": "user",
                "email": "user@example.com",
                "firstName": "Regular",
                "lastName": "User",
                "enabled": True,
                "emailVerified": True,
                "credentials": [{"type": "password", "value": "user123", "temporary": False}],
                "roles": ["user"],
                "teams": ["data-team"]
            },
            {
                "username": "user2",
                "email": "user2@example.com",
                "firstName": "User",
                "lastName": "One",
                "enabled": True,
                "emailVerified": True,
                "credentials": [{"type": "password", "value": "user123", "temporary": False}],
                "roles": [],
                "teams": []
            },
            {
                "username": "user3",
                "email": "user3@example.com",
                "firstName": "User",
                "lastName": "Two",
                "enabled": True,
                "emailVerified": True,
                "credentials": [{"type": "password", "value": "user123", "temporary": False}],
                "roles": [],
                "teams": []
            }
        ]

        success = True
        for user_data in users:
            # Extract roles and teams
            user_roles = user_data.pop("roles")
            user_teams = user_data.pop("teams")

            # Create user
            url = f"{self.base_url}/admin/realms/{self.realm_name}/users"
            response = requests.post(url, headers=headers, json=user_data, verify=False)

            if response.status_code == 201:
                print(f"✓ Created user: {user_data['username']}")

                # Get user ID and assign roles and teams
                user_id = self.get_user_id(user_data['username'])
                if user_id:
                    self.assign_user_roles(user_id, user_roles)
                    for team in user_teams:
                        group_id = self.get_group_id(team)
                        if group_id:
                            self.assign_user_to_group(user_id, group_id)

            elif response.status_code == 409:
                print(f"✓ User {user_data['username']} already exists")
            else:
                print(f"✗ Failed to create user {user_data['username']}: {response.text}")
                success = False

        return success

    def get_user_id(self, username: str) -> Optional[str]:
        """Get user ID by username"""
        headers = {
            'Authorization': f'Bearer {self.admin_token}',
            'Content-Type': 'application/json'
        }

        url = f"{self.base_url}/admin/realms/{self.realm_name}/users?username={username}"
        response = requests.get(url, headers=headers, verify=False)

        if response.status_code == 200:
            users = response.json()
            if users:
                return users[0]['id']
        return None

    def assign_user_roles(self, user_id: str, role_names: list) -> bool:
        """Assign roles to a user"""
        headers = {
            'Authorization': f'Bearer {self.admin_token}',
            'Content-Type': 'application/json'
        }

        # Get role objects
        roles = []
        for role_name in role_names:
            url = f"{self.base_url}/admin/realms/{self.realm_name}/roles/{role_name}"
            response = requests.get(url, headers=headers, verify=False)
            if response.status_code == 200:
                roles.append(response.json())

        if not roles:
            return False

        # Assign roles
        url = f"{self.base_url}/admin/realms/{self.realm_name}/users/{user_id}/role-mappings/realm"
        response = requests.post(url, headers=headers, json=roles, verify=False)

        return response.status_code == 204

    def setup_all(self) -> bool:
        """Run complete setup"""
        print("🚀 Starting Keycloak setup for LlamaStack demo...")

        try:
            self.admin_token = self.get_admin_token()
            print("✓ Authenticated as admin")

            if not self.create_realm():
                return False

            if not self.create_client():
                return False

            if not self.create_roles():
                return False

            if not self.create_groups():
                return False

            if not self.create_protocol_mappers():
                return False

            if not self.create_users():
                return False

            # Display client secret
            client_secret = self.get_client_secret()
            if client_secret:
                print(f"\n📋 Configuration Summary:")
                print(f"   Realm: {self.realm_name}")
                print(f"   Client ID: {self.client_id}")
                print(f"   Client Secret: {client_secret}")
                print(f"   JWKS URI: {self.base_url}/realms/{self.realm_name}/protocol/openid-connect/certs")
                print(f"   Issuer: {self.base_url}/realms/{self.realm_name}")
                print(f"   Token Endpoint: {self.base_url}/realms/{self.realm_name}/protocol/openid-connect/token")

                print(f"\n👥 Demo Users:")
                print(f"   admin / admin123 (role: admin, team: platform-team)")
                print(f"   developer / dev123 (role: developer, team: ml-team)")
                print(f"   developer2 / dev223 (role: developer, team: ml-team)")
                print(f"   developer3 / dev323 (role: developer, team: data-team)")
                print(f"   user / user123 (role: user, team: data-team)")
                print(f"   user2 / user123 (no role, no team)")
                print(f"   user3 / user123 (no role, no team)")

            print("\n✅ Keycloak setup completed successfully!")
            return True

        except Exception as e:
            print(f"✗ Setup failed: {e}")
            return False

def main():
    keycloak_url = os.getenv('KEYCLOAK_URL', 'https://kc-keycloak.com')
    admin_password = os.getenv('KEYCLOAK_ADMIN_PASSWORD', 'dummy')

    print(f"Keycloak URL: {keycloak_url}")

    setup = KeycloakSetup(keycloak_url, admin_password)
    success = setup.setup_all()

    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()
