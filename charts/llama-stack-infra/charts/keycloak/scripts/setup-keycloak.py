#!/usr/bin/env python3
"""
Keycloak Setup Script for LlamaStack Auth Demo (Helm in-cluster version)

Configures Keycloak with the necessary realm, client, roles, and users.
All passwords are read from environment variables injected by the Helm chart.

Environment Variables:
    KEYCLOAK_URL: Keycloak base URL (default: http://keycloak:8080)
    KEYCLOAK_ADMIN_PASSWORD: Admin password (required)
    KEYCLOAK_CLIENT_SECRET: Client secret to set (required)
    KEYCLOAK_PASSWORD: Demo admin user password (required)
    KEYCLOAK_DEMO_PASSWORD: Demo regular user password (required)
"""

import os
import sys
import json
import requests
import urllib3
from typing import Optional

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


class KeycloakSetup:
    def __init__(self, base_url: str, admin_password: str, client_secret: str,
                 demo_admin_password: str, demo_user_password: str):
        self.base_url = base_url.rstrip('/')
        self.admin_password = admin_password
        self.client_secret = client_secret
        self.demo_admin_password = demo_admin_password
        self.demo_user_password = demo_user_password
        self.admin_token = None
        self.realm_name = "llamastack-demo"
        self.client_id = "llamastack"

    def get_admin_token(self) -> str:
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
            print(f"Created realm: {self.realm_name}")
            return True
        elif response.status_code == 409:
            print(f"Realm {self.realm_name} already exists")
            return True
        else:
            print(f"Failed to create realm: {response.text}")
            return False

    def create_client(self) -> bool:
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
            print(f"Created client: {self.client_id}")
            return True
        elif response.status_code == 409:
            print(f"Client {self.client_id} already exists")
            return True
        else:
            print(f"Failed to create client: {response.text}")
            return False

    def get_client_uuid(self) -> Optional[str]:
        headers = {
            'Authorization': f'Bearer {self.admin_token}',
            'Content-Type': 'application/json'
        }
        url = f"{self.base_url}/admin/realms/{self.realm_name}/clients"
        response = requests.get(url, headers=headers, verify=False)
        if response.status_code == 200:
            for client in response.json():
                if client['clientId'] == self.client_id:
                    return client['id']
        return None

    def set_client_secret(self, secret: str) -> bool:
        client_uuid = self.get_client_uuid()
        if not client_uuid:
            return False
        headers = {
            'Authorization': f'Bearer {self.admin_token}',
            'Content-Type': 'application/json'
        }
        url = f"{self.base_url}/admin/realms/{self.realm_name}/clients/{client_uuid}"
        response = requests.get(url, headers=headers, verify=False)
        if response.status_code != 200:
            print(f"Failed to get client: {response.text}")
            return False
        client_repr = response.json()
        client_repr['secret'] = secret
        response = requests.put(url, headers=headers, json=client_repr, verify=False)
        if response.status_code == 204:
            print("Set custom client secret")
            return True
        else:
            print(f"Failed to set client secret: {response.status_code} - {response.text}")
            return False

    def create_roles(self) -> bool:
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
                print(f"Created role: {role['name']}")
            elif response.status_code == 409:
                print(f"Role {role['name']} already exists")
            else:
                print(f"Failed to create role {role['name']}: {response.text}")
                success = False
        return success

    def create_protocol_mappers(self) -> bool:
        client_uuid = self.get_client_uuid()
        if not client_uuid:
            print("Cannot create protocol mappers: client not found")
            return False
        headers = {
            'Authorization': f'Bearer {self.admin_token}',
            'Content-Type': 'application/json'
        }
        mappers = [
            {
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
            },
            {
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
        ]
        url = f"{self.base_url}/admin/realms/{self.realm_name}/clients/{client_uuid}/protocol-mappers/models"
        success = True
        for mapper in mappers:
            response = requests.post(url, headers=headers, json=mapper, verify=False)
            if response.status_code == 201:
                print(f"Created protocol mapper: {mapper['name']}")
            elif response.status_code == 409:
                print(f"Protocol mapper {mapper['name']} already exists")
            else:
                print(f"Failed to create protocol mapper {mapper['name']}: {response.text}")
                success = False
        return success

    def create_groups(self) -> bool:
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
                print(f"Created group: {group['name']}")
            elif response.status_code == 409:
                print(f"Group {group['name']} already exists")
            else:
                print(f"Failed to create group {group['name']}: {response.text}")
                success = False
        return success

    def get_group_id(self, group_name: str) -> Optional[str]:
        headers = {
            'Authorization': f'Bearer {self.admin_token}',
            'Content-Type': 'application/json'
        }
        url = f"{self.base_url}/admin/realms/{self.realm_name}/groups"
        response = requests.get(url, headers=headers, verify=False)
        if response.status_code == 200:
            for group in response.json():
                if group['name'] == group_name:
                    return group['id']
        return None

    def assign_user_to_group(self, user_id: str, group_id: str) -> bool:
        headers = {
            'Authorization': f'Bearer {self.admin_token}',
            'Content-Type': 'application/json'
        }
        url = f"{self.base_url}/admin/realms/{self.realm_name}/users/{user_id}/groups/{group_id}"
        response = requests.put(url, headers=headers, verify=False)
        return response.status_code == 204

    def get_user_id(self, username: str) -> Optional[str]:
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
        headers = {
            'Authorization': f'Bearer {self.admin_token}',
            'Content-Type': 'application/json'
        }
        roles = []
        for role_name in role_names:
            url = f"{self.base_url}/admin/realms/{self.realm_name}/roles/{role_name}"
            response = requests.get(url, headers=headers, verify=False)
            if response.status_code == 200:
                roles.append(response.json())
        if not roles:
            return False
        url = f"{self.base_url}/admin/realms/{self.realm_name}/users/{user_id}/role-mappings/realm"
        response = requests.post(url, headers=headers, json=roles, verify=False)
        return response.status_code == 204

    def create_users(self) -> bool:
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
                "credentials": [{"type": "password", "value": self.demo_admin_password, "temporary": False}],
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
                "credentials": [{"type": "password", "value": self.demo_user_password, "temporary": False}],
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
                "credentials": [{"type": "password", "value": self.demo_user_password, "temporary": False}],
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
                "credentials": [{"type": "password", "value": self.demo_user_password, "temporary": False}],
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
                "credentials": [{"type": "password", "value": self.demo_user_password, "temporary": False}],
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
                "credentials": [{"type": "password", "value": self.demo_user_password, "temporary": False}],
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
                "credentials": [{"type": "password", "value": self.demo_user_password, "temporary": False}],
                "roles": [],
                "teams": []
            }
        ]
        success = True
        for user_data in users:
            user_roles = user_data.pop("roles")
            user_teams = user_data.pop("teams")
            url = f"{self.base_url}/admin/realms/{self.realm_name}/users"
            response = requests.post(url, headers=headers, json=user_data, verify=False)
            if response.status_code == 201:
                print(f"Created user: {user_data['username']}")
                user_id = self.get_user_id(user_data['username'])
                if user_id:
                    self.assign_user_roles(user_id, user_roles)
                    for team in user_teams:
                        group_id = self.get_group_id(team)
                        if group_id:
                            self.assign_user_to_group(user_id, group_id)
            elif response.status_code == 409:
                print(f"User {user_data['username']} already exists")
            else:
                print(f"Failed to create user {user_data['username']}: {response.text}")
                success = False
        return success

    def setup_all(self) -> bool:
        print("Starting Keycloak setup for LlamaStack demo...")
        try:
            self.admin_token = self.get_admin_token()
            print("Authenticated as admin")

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
            if self.client_secret:
                if not self.set_client_secret(self.client_secret):
                    print("Warning: Failed to set persistent client secret")

            print("\nKeycloak setup completed successfully!")
            print(f"  Realm: {self.realm_name}")
            print(f"  Client ID: {self.client_id}")
            print(f"  JWKS URI: {self.base_url}/realms/{self.realm_name}/protocol/openid-connect/certs")
            print(f"  Issuer: {self.base_url}/realms/{self.realm_name}")
            return True
        except Exception as e:
            print(f"Setup failed: {e}")
            return False


def main():
    keycloak_url = os.environ.get('KEYCLOAK_URL', 'http://keycloak:8080')
    admin_password = os.environ.get('KEYCLOAK_ADMIN_PASSWORD')
    client_secret = os.environ.get('KEYCLOAK_CLIENT_SECRET')
    demo_admin_password = os.environ.get('KEYCLOAK_PASSWORD')
    demo_user_password = os.environ.get('KEYCLOAK_DEMO_PASSWORD')

    if not admin_password:
        print("Error: KEYCLOAK_ADMIN_PASSWORD environment variable is required")
        sys.exit(1)

    print(f"Keycloak URL: {keycloak_url}")

    setup = KeycloakSetup(
        keycloak_url, admin_password, client_secret,
        demo_admin_password or admin_password,
        demo_user_password or admin_password
    )
    success = setup.setup_all()
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
